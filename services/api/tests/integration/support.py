"""Helpers for tests against the real local Supabase stack (`make check-integration`).

Privileged keys are used only here, to provision and remove synthetic users and
the temporary table/bucket. Code under test receives user tokens and the public
key only. Missing configuration fails the run; nothing is skipped.
"""

import os
import subprocess
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Any

import httpx2
import pytest
from fastapi import FastAPI

from app.settings import SupabaseSettings

ISSUER = "http://127.0.0.1:54321/auth/v1"
FIXTURE_PASSWORD = "Fixture-password-1"
_REQUIRED_ENV = (
    "SB_API_URL",
    "SB_PUBLISHABLE_KEY",
    "SB_SECRET_KEY",
    "SB_ANON_KEY",
    "SB_SERVICE_ROLE_KEY",
    "SB_JWT_SECRET",
    "SUPABASE_BIN",
)


@dataclass(frozen=True)
class Stack:
    url: str
    publishable_key: str
    secret_key: str = field(repr=False)
    anon_key: str = field(repr=False)
    service_role_key: str = field(repr=False)
    jwt_secret: str = field(repr=False)
    supabase_bin: str

    @property
    def settings(self) -> SupabaseSettings:
        return SupabaseSettings(
            url=self.url, publishable_key=self.publishable_key, jwt_issuer=ISSUER
        )

    def admin_headers(self) -> dict[str, str]:
        return {"apikey": self.secret_key, "Authorization": f"Bearer {self.secret_key}"}

    def public_headers(self) -> dict[str, str]:
        return {"apikey": self.publishable_key}


@dataclass(frozen=True)
class StackUser:
    email: str
    user_id: str
    access_token: str = field(repr=False)
    refresh_token: str = field(repr=False)

    def headers(self, stack: Stack) -> dict[str, str]:
        return {**stack.public_headers(), "Authorization": f"Bearer {self.access_token}"}


def load_stack() -> Stack:
    missing = [name for name in _REQUIRED_ENV if not os.environ.get(name)]
    if missing:
        pytest.fail(
            f"Integration environment missing {', '.join(missing)}; run `make check-integration`."
        )
    env = os.environ
    return Stack(
        url=env["SB_API_URL"].rstrip("/"),
        publishable_key=env["SB_PUBLISHABLE_KEY"],
        secret_key=env["SB_SECRET_KEY"],
        anon_key=env["SB_ANON_KEY"],
        service_role_key=env["SB_SERVICE_ROLE_KEY"],
        jwt_secret=env["SB_JWT_SECRET"],
        supabase_bin=env["SUPABASE_BIN"],
    )


def run_sql(stack: Stack, sql: str) -> None:
    """Run one SQL statement on the local database as the fixture operator."""
    subprocess.run(  # noqa: S603 - fixed binary from the Makefile, local stack only
        [stack.supabase_bin, "db", "query", "--local", "--agent", "no", sql],
        check=True,
        capture_output=True,
        timeout=60,
    )


# --- users -----------------------------------------------------------------


def create_user(http: httpx2.Client, stack: Stack, email: str) -> str:
    response = http.post(
        f"{stack.url}/auth/v1/admin/users",
        headers=stack.admin_headers(),
        json={"email": email, "password": FIXTURE_PASSWORD, "email_confirm": True},
    )
    response.raise_for_status()
    return str(response.json()["id"])


def delete_user(http: httpx2.Client, stack: Stack, user_id: str) -> None:
    http.delete(f"{stack.url}/auth/v1/admin/users/{user_id}", headers=stack.admin_headers())


def find_user(http: httpx2.Client, stack: Stack, email: str) -> dict[str, Any] | None:
    response = http.get(
        f"{stack.url}/auth/v1/admin/users",
        headers=stack.admin_headers(),
        params={"per_page": "1000"},
    )
    response.raise_for_status()
    for user in response.json()["users"]:
        if user.get("email") == email:
            assert isinstance(user, dict)
            return user
    return None


def user_exists(http: httpx2.Client, stack: Stack, email: str) -> bool:
    response = http.get(
        f"{stack.url}/auth/v1/admin/users",
        headers=stack.admin_headers(),
        params={"per_page": "1000"},
    )
    response.raise_for_status()
    return any(user.get("email") == email for user in response.json()["users"])


def sign_in(http: httpx2.Client, stack: Stack, email: str) -> StackUser:
    """A new session for a fixture user, through the same password grant the app uses."""
    response = http.post(
        f"{stack.url}/auth/v1/token",
        params={"grant_type": "password"},
        headers=stack.public_headers(),
        json={"email": email, "password": FIXTURE_PASSWORD},
    )
    response.raise_for_status()
    body = response.json()
    return StackUser(
        email=email,
        user_id=body["user"]["id"],
        access_token=body["access_token"],
        refresh_token=body["refresh_token"],
    )


def unique_email(label: str) -> str:
    return f"{label}-{uuid.uuid4().hex[:10]}@example.test"


def do_block(statements: list[str]) -> str:
    body = "\n".join(
        f"{s};" if s.startswith("perform ") else f"execute $sql${s}$sql$;" for s in statements
    )
    return f"do $fixture$\nbegin\n{body}\nend\n$fixture$"


def wait_until_exposed(http: httpx2.Client, stack: Stack, user: StackUser, table: str) -> None:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if http.get(f"{stack.url}/rest/v1/{table}", headers=user.headers(stack)).status_code == 200:
            return
        time.sleep(0.25)
    raise AssertionError(f"Data API did not expose {table}")


# --- the API under test ------------------------------------------------------


class RecordingTransport(httpx2.AsyncBaseTransport):
    """Passes requests to the network and records their headers."""

    def __init__(self) -> None:
        self._inner = httpx2.AsyncHTTPTransport()
        self.sent_headers: list[dict[str, str]] = []

    async def handle_async_request(self, request: httpx2.Request) -> httpx2.Response:
        self.sent_headers.append(dict(request.headers))
        return await self._inner.handle_async_request(request)

    async def aclose(self) -> None:
        await self._inner.aclose()


@asynccontextmanager
async def running_client(application: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    async with application.router.lifespan_context(application):
        transport = httpx2.ASGITransport(app=application)
        async with httpx2.AsyncClient(transport=transport, base_url="http://testserver") as client:
            yield client
