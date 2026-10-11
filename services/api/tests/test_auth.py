"""Unit tests for bearer authentication with a fake Supabase Auth server."""

import asyncio
import random
import uuid
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager

import httpx2
import pytest
from fastapi import FastAPI

from app.main import create_app
from app.settings import SupabaseSettings
from tokens import ISSUER, make_token, subject_of

SETTINGS = SupabaseSettings(
    url="http://127.0.0.1:54321", publishable_key="sb_publishable_test", jwt_issuer=ISSUER
)
ORIGIN = "http://localhost:3000"
pytestmark = pytest.mark.anyio


class FakeAuthServer:
    """Accepts only registered tokens, like `GET /auth/v1/user`."""

    def __init__(self) -> None:
        self.users: dict[str, dict[str, object]] = {}
        self.requests: list[httpx2.Request] = []
        self.override: Callable[[httpx2.Request], httpx2.Response] | None = None
        self.max_delay = 0.0

    def register(self, token: str, **user: object) -> None:
        self.users[token] = {"id": subject_of(token), "aud": "authenticated", **user}

    async def handle(self, request: httpx2.Request) -> httpx2.Response:
        self.requests.append(request)
        if self.max_delay:
            await asyncio.sleep(random.uniform(0, self.max_delay))  # noqa: S311
        if self.override:
            return self.override(request)
        token = request.headers.get("authorization", "").removeprefix("Bearer ")
        user = self.users.get(token)
        if user is None:
            return httpx2.Response(403, json={"code": 403, "error_code": "bad_jwt"})
        return httpx2.Response(200, json=user)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def auth_server() -> FakeAuthServer:
    return FakeAuthServer()


@asynccontextmanager
async def running(application: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    async with application.router.lifespan_context(application):
        transport = httpx2.ASGITransport(app=application)
        async with httpx2.AsyncClient(transport=transport, base_url="http://testserver") as client:
            yield client


@pytest.fixture
async def api(auth_server: FakeAuthServer) -> AsyncIterator[httpx2.AsyncClient]:
    application = create_app(
        [ORIGIN], SETTINGS, http_transport=httpx2.MockTransport(auth_server.handle)
    )
    async with running(application) as client:
        yield client


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def test_me_returns_provider_verified_identity(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    token = make_token()
    auth_server.register(token)

    response = await api.get("/api/v1/me", headers=bearer(token))

    assert response.status_code == 200
    assert response.json() == {"user_id": subject_of(token)}
    assert response.headers["cache-control"] == "no-store"
    [request] = auth_server.requests
    assert request.headers["authorization"] == f"Bearer {token}"
    assert request.headers["apikey"] == "sb_publishable_test"


@pytest.mark.parametrize("header", [None, "Basic abc", "Bearer "])
async def test_missing_or_non_bearer_token_is_401(
    api: httpx2.AsyncClient, header: str | None
) -> None:
    response = await api.get("/api/v1/me", headers={"Authorization": header} if header else {})

    assert response.status_code == 401
    assert response.headers["www-authenticate"].startswith('Bearer realm="api"')


@pytest.mark.parametrize(
    "token",
    [
        "not-a-jwt",
        make_token(alg="HS256"),
        make_token(alg="none"),
        make_token(iss="https://other-project.supabase.co/auth/v1"),
        make_token(role="service_role"),
        make_token(is_anonymous=True),
        make_token(exp=1),
    ],
)
async def test_unacceptable_tokens_fail_without_trusting_claims(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer, token: str
) -> None:
    # Even a provider that would accept anything must not rescue these tokens.
    auth_server.override = lambda request: httpx2.Response(
        200, json={"id": str(uuid.uuid4()), "aud": "authenticated"}
    )

    response = await api.get("/api/v1/me", headers=bearer(token))

    assert response.status_code == 401


async def test_provider_rejection_or_other_identity_is_401(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    unknown = await api.get("/api/v1/me", headers=bearer(make_token()))
    auth_server.override = lambda request: httpx2.Response(
        200, json={"id": str(uuid.uuid4()), "aud": "authenticated"}
    )
    someone_else = await api.get("/api/v1/me", headers=bearer(make_token()))

    assert unknown.status_code == someone_else.status_code == 401


@pytest.mark.parametrize(
    "outage",
    [
        lambda request: httpx2.Response(503),
        lambda request: httpx2.Response(302, headers={"location": "http://evil.example/"}),
        lambda request: httpx2.Response(200, text="not json"),
    ],
)
async def test_provider_outage_fails_closed_with_503(
    api: httpx2.AsyncClient,
    auth_server: FakeAuthServer,
    outage: Callable[[httpx2.Request], httpx2.Response],
) -> None:
    token = make_token()
    auth_server.register(token)
    auth_server.override = outage

    response = await api.get("/api/v1/me", headers=bearer(token))

    assert response.status_code == 503
    assert token not in response.text


async def test_token_never_appears_in_logs(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level("DEBUG")
    token = make_token()
    auth_server.register(token)

    await api.get("/api/v1/me", headers=bearer(token))

    assert caplog.records
    assert token.split(".")[1] not in caplog.text


async def test_shipped_app_exposes_only_known_routes() -> None:
    openapi_paths = set(create_app([ORIGIN], SETTINGS).openapi()["paths"])

    assert openapi_paths == {"/health", "/api/v1/me", "/api/v1/ideas", "/api/v1/ideas/{idea_id}"}
