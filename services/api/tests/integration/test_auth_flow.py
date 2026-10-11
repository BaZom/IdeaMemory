"""Username + password accounts and API token checks against the real stack.
The app maps a username to `<username>@users.invalid`."""

from collections.abc import AsyncIterator

import httpx2
import pytest
from support import Stack, StackUser, running_client, sign_in, unique_email

from app.main import create_app
from tokens import make_token

pytestmark = pytest.mark.integration

PASSWORD = "Correct-horse-battery-1"


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
async def api(stack: Stack) -> AsyncIterator[httpx2.AsyncClient]:
    async with running_client(create_app([], stack.settings)) as client:
        yield client


def account(label: str) -> str:
    return unique_email(label).replace("@example.test", "@users.invalid")


def sign_up(http: httpx2.Client, stack: Stack, email: str, password: str) -> httpx2.Response:
    return http.post(
        f"{stack.url}/auth/v1/signup",
        headers=stack.public_headers(),
        json={"email": email, "password": password},
    )


def password_sign_in(
    http: httpx2.Client, stack: Stack, email: str, password: str
) -> httpx2.Response:
    return http.post(
        f"{stack.url}/auth/v1/token",
        params={"grant_type": "password"},
        headers=stack.public_headers(),
        json={"email": email, "password": password},
    )


def test_sign_up_signs_in_and_sign_in_works_later(
    http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    email = account("signup")

    signed_up = sign_up(http, stack, email, PASSWORD)

    assert signed_up.status_code == 200
    assert signed_up.json()["access_token"]  # signed in immediately, no confirmation
    provisioned.append(signed_up.json()["user"]["id"])
    later = password_sign_in(http, stack, email, PASSWORD)
    assert later.json()["user"]["id"] == signed_up.json()["user"]["id"]


def test_wrong_password_unknown_user_and_taken_username_are_refused(
    http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    email = account("taken")
    provisioned.append(sign_up(http, stack, email, PASSWORD).json()["user"]["id"])

    wrong = password_sign_in(http, stack, email, "Not-the-password-1")
    unknown = password_sign_in(http, stack, account("nobody"), PASSWORD)
    again = sign_up(http, stack, email, "Someone-elses-pass-1")
    short = sign_up(http, stack, account("short"), "short1")

    assert wrong.json()["error_code"] == unknown.json()["error_code"] == "invalid_credentials"
    assert again.json()["error_code"] == "user_already_exists"
    assert short.json()["error_code"] == "weak_password"
    assert password_sign_in(http, stack, email, PASSWORD).status_code == 200


@pytest.mark.anyio
async def test_api_accepts_real_tokens_and_refuses_forged_ones(
    api: httpx2.AsyncClient, http: httpx2.Client, stack: Stack, user_a: StackUser
) -> None:
    async def me(token: str) -> httpx2.Response:
        return await api.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})

    assert (await me(user_a.access_token)).json() == {"user_id": user_a.user_id}
    # The local provider itself accepts tokens signed with its public legacy
    # secret; the API must not.
    forged = make_token(stack.jwt_secret, alg="HS256", sub=user_a.user_id)
    for token in (forged, stack.anon_key, stack.service_role_key, "not-a-token"):
        assert (await me(token)).status_code == 401

    session = sign_in(http, stack, user_a.email)
    http.post(
        f"{stack.url}/auth/v1/logout", params={"scope": "local"}, headers=session.headers(stack)
    )
    assert (await me(session.access_token)).status_code == 401  # signed out
