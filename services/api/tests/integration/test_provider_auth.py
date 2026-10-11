"""T002-AC1/AC2: self-service username + password sign-up and sign-in, and the
provider-side rules behind them. The app maps a username to
`<username>@users.invalid` (see apps/mobile/lib/auth/username.dart)."""

from collections.abc import AsyncIterator

import httpx2
import pytest
from support import (
    FIXTURE_PASSWORD,
    Stack,
    create_user,
    find_user,
    running_client,
    sign_in,
    unique_email,
)

from app.main import create_app

pytestmark = pytest.mark.integration

PASSWORD = "Correct-horse-battery-1"


def account(label: str) -> str:
    """The provider identity the app uses for a fresh username."""
    return unique_email(label).replace("@example.test", "@users.invalid")


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
async def api(stack: Stack) -> AsyncIterator[httpx2.AsyncClient]:
    async with running_client(create_app([], stack.settings)) as client:
        yield client


def sign_up_request(
    http: httpx2.Client, stack: Stack, email: str, password: str
) -> httpx2.Response:
    """What the app's Sign up sends."""
    return http.post(
        f"{stack.url}/auth/v1/signup",
        headers=stack.public_headers(),
        json={"email": email, "password": password},
    )


def sign_in_request(
    http: httpx2.Client, stack: Stack, email: str, password: str
) -> httpx2.Response:
    """What the app's Sign in sends."""
    return http.post(
        f"{stack.url}/auth/v1/token",
        params={"grant_type": "password"},
        headers=stack.public_headers(),
        json={"email": email, "password": password},
    )


@pytest.mark.anyio
async def test_new_user_signs_up_and_can_use_the_app(
    http: httpx2.Client,
    stack: Stack,
    provisioned: list[str],
    api: httpx2.AsyncClient,
    fixture_table: str,
) -> None:
    email = account("signup")

    response = sign_up_request(http, stack, email, PASSWORD)

    assert response.status_code == 200
    session = response.json()
    assert session["user"]["email"] == email
    provisioned.append(session["user"]["id"])

    me = await api.get("/api/v1/me", headers={"Authorization": f"Bearer {session['access_token']}"})
    assert me.json() == {"user_id": session["user"]["id"]}

    created = http.post(
        f"{stack.url}/rest/v1/{fixture_table}",
        headers={
            **stack.public_headers(),
            "Authorization": f"Bearer {session['access_token']}",
            "Prefer": "return=representation",
        },
        json={"note": "first-note"},
    )
    assert created.status_code == 201
    assert created.json()[0]["owner_id"] == session["user"]["id"]


def test_returning_user_signs_in_with_password(
    http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    email = account("returning")
    signed_up = sign_up_request(http, stack, email, PASSWORD)
    provisioned.append(signed_up.json()["user"]["id"])

    response = sign_in_request(http, stack, email, PASSWORD)

    assert response.status_code == 200
    assert response.json()["user"]["id"] == signed_up.json()["user"]["id"]


def test_wrong_password_and_unknown_email_look_the_same(
    http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    email = unique_email("wrong")
    provisioned.append(create_user(http, stack, email))

    wrong = sign_in_request(http, stack, email, "Not-the-password-1")
    unknown = sign_in_request(http, stack, account("nobody"), PASSWORD)

    for response in (wrong, unknown):
        assert response.status_code == 400
        assert response.json()["error_code"] == "invalid_credentials"
        assert "access_token" not in response.text


def test_existing_email_cannot_be_signed_up_again(
    http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    email = unique_email("taken")
    provisioned.append(create_user(http, stack, email))

    again = sign_up_request(http, stack, email, "Someone-elses-pass-1")

    assert again.status_code == 422
    assert again.json()["error_code"] == "user_already_exists"
    assert "access_token" not in again.text
    # The owner's password is unchanged and the new one does not work.
    assert sign_in_request(http, stack, email, FIXTURE_PASSWORD).status_code == 200
    assert sign_in_request(http, stack, email, "Someone-elses-pass-1").status_code == 400


def test_short_password_is_refused(http: httpx2.Client, stack: Stack) -> None:
    email = account("short")

    response = sign_up_request(http, stack, email, "short1")

    assert response.status_code == 422
    assert response.json()["error_code"] == "weak_password"
    assert find_user(http, stack, email) is None


def test_anonymous_sign_in_is_refused(http: httpx2.Client, stack: Stack) -> None:
    response = http.post(f"{stack.url}/auth/v1/signup", headers=stack.public_headers(), json={})

    assert response.status_code == 422
    assert "access_token" not in response.text


def test_refresh_rotates_and_logout_revokes_refresh(
    http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    email = unique_email("refresh")
    provisioned.append(create_user(http, stack, email))
    user = sign_in(http, stack, email)

    refreshed = http.post(
        f"{stack.url}/auth/v1/token",
        params={"grant_type": "refresh_token"},
        headers=stack.public_headers(),
        json={"refresh_token": user.refresh_token},
    )
    assert refreshed.status_code == 200
    new_refresh = refreshed.json()["refresh_token"]
    assert new_refresh != user.refresh_token

    logout = http.post(
        f"{stack.url}/auth/v1/logout",
        params={"scope": "local"},
        headers={
            **stack.public_headers(),
            "Authorization": f"Bearer {refreshed.json()['access_token']}",
        },
    )
    assert logout.status_code == 204

    after = http.post(
        f"{stack.url}/auth/v1/token",
        params={"grant_type": "refresh_token"},
        headers=stack.public_headers(),
        json={"refresh_token": new_refresh},
    )
    assert after.status_code == 400
    assert after.json()["error_code"] == "refresh_token_not_found"
