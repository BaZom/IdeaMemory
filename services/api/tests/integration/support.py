"""Helpers for tests against the real local Supabase stack (`make check-integration`).

Privileged keys are used only here, to provision and remove synthetic users.
Code under test receives user tokens and the public key only. Missing
configuration fails the run; nothing is skipped.
"""

import json
import os
import subprocess
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


def query_sql(stack: Stack, sql: str) -> list[dict[str, Any]]:
    """Run one SQL query as the fixture operator and return its rows."""
    result = subprocess.run(  # noqa: S603 - fixed binary from the Makefile, local stack only
        [stack.supabase_bin, "db", "query", "--local", "--agent", "no", "-o", "json", sql],
        check=True,
        capture_output=True,
        timeout=60,
    )
    rows: list[dict[str, Any]] = json.loads(result.stdout)
    return rows


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


# --- the API under test ------------------------------------------------------


@asynccontextmanager
async def running_client(application: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    async with application.router.lifespan_context(application):
        transport = httpx2.ASGITransport(app=application)
        async with httpx2.AsyncClient(transport=transport, base_url="http://testserver") as client:
            yield client
