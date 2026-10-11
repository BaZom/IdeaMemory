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
    assert response.headers["x-request-id"]


async def test_provider_receives_token_and_public_key_only(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    token = make_token()
    auth_server.register(token)

    await api.get("/api/v1/me", headers=bearer(token))

    [request] = auth_server.requests
    assert str(request.url) == "http://127.0.0.1:54321/auth/v1/user"
    assert request.method == "GET"
    assert request.headers["authorization"] == f"Bearer {token}"
    assert request.headers["apikey"] == "sb_publishable_test"


async def test_missing_token_is_401_with_challenge(api: httpx2.AsyncClient) -> None:
    response = await api.get("/api/v1/me")

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == 'Bearer realm="api"'
    assert response.headers["cache-control"] == "no-store"
    assert response.json() == {
        "error": {"code": "missing_token", "message": "Authentication is required."}
    }


@pytest.mark.parametrize(
    "header", ["Basic dXNlcjpwYXNz", "Bearer", "Bearer   ", "Token abc.def.ghi", "bearer"]
)
async def test_non_bearer_authorization_is_401(api: httpx2.AsyncClient, header: str) -> None:
    response = await api.get("/api/v1/me", headers={"Authorization": header})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"
    assert 'error="invalid_token"' in response.headers["www-authenticate"]


async def test_token_rejected_by_provider_is_401(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    response = await api.get("/api/v1/me", headers=bearer(make_token()))

    assert response.status_code == 401
    assert response.json() == {
        "error": {"code": "invalid_token", "message": "The access token is invalid or expired."}
    }
    assert len(auth_server.requests) == 1


@pytest.mark.parametrize(
    "token",
    [
        "not-a-jwt",
        "a.b",
        "a.b.c.d",
        "!!.??.##",
        "e30.bm90LWpzb24.c2ln",  # payload is not JSON
        "W10.W10.c2ln",  # JSON arrays, not objects
        "x" * 9000,
        make_token(alg="HS256"),
        make_token(alg="HS512"),
        make_token(alg="none"),
        "W10." + make_token().split(".", 1)[1],  # header is not an object
        make_token(iss="http://127.0.0.1:54321/auth/v1/other"),
        make_token(iss="https://other-project.supabase.co/auth/v1"),
        make_token(iss=None),
        make_token(aud="other"),
        make_token(aud=["other"]),
        make_token(role="anon"),
        make_token(role="service_role"),
        make_token(role=None, sub=None),  # API-key style token
        make_token(is_anonymous=True),
        make_token(exp=1),
        make_token(exp="9999999999"),
        make_token(exp=None),
        make_token(sub="not-a-uuid"),
        make_token(sub=None),
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
    assert response.json()["error"]["code"] == "invalid_token"


async def test_audience_list_with_authenticated_is_accepted(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    token = make_token(aud=["authenticated", "other"])
    auth_server.register(token)

    response = await api.get("/api/v1/me", headers=bearer(token))

    assert response.status_code == 200


@pytest.mark.parametrize(
    "provider_user",
    [
        lambda sub: {"id": str(uuid.uuid4()), "aud": "authenticated"},  # someone else
        lambda sub: {"aud": "authenticated"},
        lambda sub: {"id": None, "aud": "authenticated"},
        lambda sub: {"id": sub, "aud": "other"},
        lambda sub: {"id": sub},
        lambda sub: {"id": sub, "aud": "authenticated", "is_anonymous": True},
    ],
)
async def test_provider_identity_must_match_token(
    api: httpx2.AsyncClient,
    auth_server: FakeAuthServer,
    provider_user: Callable[[str], dict[str, object]],
) -> None:
    token = make_token()
    body = provider_user(subject_of(token))
    auth_server.override = lambda request: httpx2.Response(200, json=body)

    response = await api.get("/api/v1/me", headers=bearer(token))

    assert response.status_code == 401


@pytest.mark.parametrize("status", [400, 401, 403])
async def test_provider_rejections_are_401(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer, status: int
) -> None:
    auth_server.override = lambda request: httpx2.Response(status, json={"msg": "no"})

    response = await api.get("/api/v1/me", headers=bearer(make_token()))

    assert response.status_code == 401


def _raise(error: Exception) -> Callable[[httpx2.Request], httpx2.Response]:
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise error

    return handler


@pytest.mark.parametrize(
    "outage",
    [
        lambda request: httpx2.Response(500),
        lambda request: httpx2.Response(502, text="<html>bad gateway</html>"),
        lambda request: httpx2.Response(503),
        lambda request: httpx2.Response(429, json={"msg": "rate limited"}),
        lambda request: httpx2.Response(404, json={"message": "no Route matched"}),
        lambda request: httpx2.Response(302, headers={"location": "http://evil.example/"}),
        lambda request: httpx2.Response(200, text="not json"),
        lambda request: httpx2.Response(200, json=["not", "an", "object"]),
        _raise(httpx2.ConnectError("refused")),
        _raise(httpx2.ReadTimeout("slow")),
        _raise(httpx2.ConnectTimeout("slow")),
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
    assert response.json() == {
        "error": {
            "code": "auth_unavailable",
            "message": "Authentication is temporarily unavailable.",
        }
    }
    assert token not in response.text


async def test_redirects_from_provider_are_not_followed(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    auth_server.override = lambda request: httpx2.Response(
        307, headers={"location": "http://evil.example/auth/v1/user"}
    )

    await api.get("/api/v1/me", headers=bearer(make_token()))

    assert [str(r.url) for r in auth_server.requests] == ["http://127.0.0.1:54321/auth/v1/user"]


async def test_concurrent_users_never_see_each_others_identity(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    tokens = [make_token() for _ in range(2)]
    for token in tokens:
        auth_server.register(token)
    auth_server.max_delay = 0.02
    calls = [tokens[i % 2] for i in range(60)]

    responses = await asyncio.gather(
        *(api.get("/api/v1/me", headers=bearer(token)) for token in calls)
    )

    for token, response in zip(calls, responses, strict=True):
        assert response.status_code == 200
        assert response.json() == {"user_id": subject_of(token)}
    for request in auth_server.requests:
        # Each provider call carried exactly one caller's credentials.
        assert request.headers["authorization"] in {f"Bearer {t}" for t in tokens}


async def test_unconfigured_auth_is_503_and_health_still_works() -> None:
    async with running(create_app([ORIGIN])) as client:
        me = await client.get("/api/v1/me", headers=bearer(make_token()))
        health = await client.get("/health")

    assert me.status_code == 503
    assert me.json()["error"]["code"] == "auth_not_configured"
    assert health.status_code == 200
    assert health.json() == {"status": "ok"}


async def test_health_does_not_contact_auth_provider(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer
) -> None:
    auth_server.override = _raise(httpx2.ConnectError("down"))

    response = await api.get("/health", headers=bearer(make_token()))

    assert response.status_code == 200
    assert auth_server.requests == []


async def test_cors_preflight_allows_authorization_for_configured_origin(
    api: httpx2.AsyncClient,
) -> None:
    response = await api.options(
        "/api/v1/me",
        headers={
            "Origin": ORIGIN,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == ORIGIN
    assert "authorization" in response.headers["access-control-allow-headers"].lower()
    assert "access-control-allow-credentials" not in response.headers


async def test_cors_preflight_rejects_unrelated_origin(api: httpx2.AsyncClient) -> None:
    response = await api.options(
        "/api/v1/me",
        headers={
            "Origin": "http://evil.example",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


async def test_token_never_appears_in_logs(
    api: httpx2.AsyncClient, auth_server: FakeAuthServer, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level("DEBUG")
    token = make_token()
    auth_server.register(token)

    await api.get("/api/v1/me", headers=bearer(token))
    await api.get("/api/v1/me", headers=bearer(make_token()))

    assert caplog.records
    assert token not in caplog.text
    assert token.split(".")[1] not in caplog.text


async def test_shipped_app_exposes_only_known_routes() -> None:
    application = create_app([ORIGIN], SETTINGS)
    paths = {getattr(route, "path", None) for route in application.routes}
    openapi_paths = set(application.openapi()["paths"])

    assert openapi_paths == {"/health", "/api/v1/me"}
    assert paths <= {
        "/health",
        "/api/v1/me",
        "/openapi.json",
        "/docs",
        "/docs/oauth2-redirect",
        "/redoc",
    }


async def test_settings_repr_hides_key() -> None:
    assert "sb_publishable_test" not in repr(SETTINGS)
