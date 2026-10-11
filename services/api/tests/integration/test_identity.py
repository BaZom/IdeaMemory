"""T002-AC4/AC5: `/api/v1/me` against the real provider, including forged and
revoked tokens, outages and concurrent users."""

import asyncio
import base64
import json
import time
from collections.abc import AsyncIterator

import httpx2
import pytest
from support import (
    ISSUER,
    RecordingTransport,
    Stack,
    StackUser,
    create_user,
    delete_user,
    running_client,
    sign_in,
    unique_email,
)

from app.main import create_app
from app.settings import SupabaseSettings
from tokens import make_token

pytestmark = [pytest.mark.integration, pytest.mark.anyio]


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def transport() -> RecordingTransport:
    return RecordingTransport()


@pytest.fixture
async def api(stack: Stack, transport: RecordingTransport) -> AsyncIterator[httpx2.AsyncClient]:
    application = create_app(["http://localhost:3000"], stack.settings, http_transport=transport)
    async with running_client(application) as client:
        yield client


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def me(api: httpx2.AsyncClient, token: str) -> httpx2.Response:
    return await api.get("/api/v1/me", headers=bearer(token))


async def test_real_tokens_resolve_to_their_own_users(
    api: httpx2.AsyncClient, user_a: StackUser, user_b: StackUser
) -> None:
    for user in (user_a, user_b):
        response = await me(api, user.access_token)
        assert response.status_code == 200
        assert response.json() == {"user_id": user.user_id}
        assert response.headers["cache-control"] == "no-store"


async def test_token_minted_with_the_default_legacy_secret_is_refused(
    api: httpx2.AsyncClient, http: httpx2.Client, stack: Stack, user_a: StackUser
) -> None:
    forged = make_token(stack.jwt_secret, alg="HS256", sub=user_a.user_id)
    # The local provider itself accepts this forgery; the API must not.
    provider = http.get(
        f"{stack.url}/auth/v1/user",
        headers={**stack.public_headers(), "Authorization": f"Bearer {forged}"},
    )
    assert provider.status_code == 200

    response = await me(api, forged)

    assert response.status_code == 401


@pytest.mark.parametrize(
    "forge",
    [
        lambda stack, user: make_token(
            stack.jwt_secret, alg="HS256", sub=user.user_id, exp=int(time.time()) - 60
        ),
        lambda stack, user: make_token(
            "another-project-secret-with-at-least-32-chars", sub=user.user_id
        ),
        lambda stack, user: make_token("x", alg="ES256", sub=user.user_id),
        lambda stack, user: _with_claims(
            user.access_token, sub="00000000-0000-4000-8000-000000000000"
        ),
        lambda stack, user: _with_claims(user.access_token, exp=int(time.time()) - 60),
        lambda stack, user: _with_claims(user.access_token, iss="http://evil.example/auth/v1"),
        lambda stack, user: stack.anon_key,
        lambda stack, user: stack.service_role_key,
        lambda stack, user: stack.publishable_key,
        lambda stack, user: stack.secret_key,
    ],
    ids=[
        "expired-legacy",
        "wrong-project",
        "bad-es256-signature",
        "tampered-subject",
        "tampered-expiry",
        "tampered-issuer",
        "anon-key",
        "service-role-key",
        "publishable-key",
        "secret-key",
    ],
)
async def test_forged_and_non_user_tokens_are_refused(
    api: httpx2.AsyncClient, stack: Stack, user_a: StackUser, forge: object
) -> None:
    token = forge(stack, user_a)  # type: ignore[operator]

    response = await me(api, token)

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"


async def test_signed_out_session_is_refused_immediately(
    api: httpx2.AsyncClient, http: httpx2.Client, stack: Stack, user_a: StackUser
) -> None:
    session = sign_in(http, stack, user_a.email)  # separate session of A
    assert (await me(api, session.access_token)).status_code == 200

    logout = http.post(
        f"{stack.url}/auth/v1/logout",
        params={"scope": "local"},
        headers=session.headers(stack),
    )
    assert logout.status_code == 204

    assert (await me(api, session.access_token)).status_code == 401
    assert (await me(api, user_a.access_token)).status_code == 200  # other session unaffected


async def test_deleted_user_is_refused(
    api: httpx2.AsyncClient, http: httpx2.Client, stack: Stack
) -> None:
    email = unique_email("deleted")
    user_id = create_user(http, stack, email)
    session = sign_in(http, stack, email)
    delete_user(http, stack, user_id)

    assert (await me(api, session.access_token)).status_code == 401


async def test_unreachable_provider_fails_closed(stack: Stack, user_a: StackUser) -> None:
    unreachable = SupabaseSettings(
        url="http://127.0.0.1:9", publishable_key=stack.publishable_key, jwt_issuer=ISSUER
    )
    async with running_client(create_app([], unreachable)) as client:
        response = await me(client, user_a.access_token)
        health = await client.get("/health")

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "auth_unavailable"
    assert health.status_code == 200


async def test_concurrent_users_stay_isolated(
    api: httpx2.AsyncClient, user_a: StackUser, user_b: StackUser
) -> None:
    users = [user_a, user_b] * 20

    responses = await asyncio.gather(*(me(api, user.access_token) for user in users))

    for user, response in zip(users, responses, strict=True):
        assert response.status_code == 200
        assert response.json() == {"user_id": user.user_id}


async def test_api_never_sends_privileged_credentials(
    api: httpx2.AsyncClient,
    transport: RecordingTransport,
    stack: Stack,
    user_a: StackUser,
    user_b: StackUser,
) -> None:
    for user in (user_a, user_b):
        await me(api, user.access_token)

    assert transport.sent_headers
    privileged = {stack.secret_key, stack.service_role_key}
    for headers in transport.sent_headers:
        assert headers["apikey"] == stack.publishable_key
        assert not privileged & {value.removeprefix("Bearer ") for value in headers.values()}


def _with_claims(token: str, **changes: object) -> str:
    header, payload, signature = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    claims.update(changes)
    new_payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
    return f"{header}.{new_payload}.{signature}"
