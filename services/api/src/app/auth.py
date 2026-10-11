"""Bearer-token authentication against Supabase Auth.

Every accepted token is verified online by the configured Supabase Auth server
(`GET /auth/v1/user`), which checks the signature, signing key, expiry and that
the user still exists. Local claim checks only narrow what is accepted (issuer,
audience, role, subject); decoding a token never authenticates it on its own.
"""

import base64
import binascii
import json
import re
import time
import uuid
from dataclasses import dataclass, field
from typing import Annotated, Any

import httpx2
from fastapi import Depends, Request

from app.errors import ApiError
from app.settings import SupabaseSettings

AUTHENTICATED = "authenticated"
# Supabase signing keys are asymmetric. Shared-secret (HS*) tokens are refused
# even if the provider would accept them: a leaked or default legacy secret
# (the local stack ships a public one) could otherwise mint any identity.
ALLOWED_ALGORITHMS = frozenset({"ES256", "RS256", "EdDSA"})
PROVIDER_TIMEOUT = httpx2.Timeout(5.0)
MAX_TOKEN_LENGTH = 8192
_JWT_SHAPE = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$")


@dataclass(frozen=True)
class VerifiedUser:
    user_id: uuid.UUID
    # Request-local credential for acting as this user; never log or persist it.
    access_token: str = field(repr=False)


class InvalidTokenError(Exception):
    """The token is malformed, unacceptable or rejected by the provider."""


class AuthUnavailableError(Exception):
    """The provider could not give a trustworthy answer; fail closed."""


def _decode_segment(segment: str) -> Any:
    padded = segment + "=" * (-len(segment) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(padded))
    except (binascii.Error, ValueError) as error:
        raise InvalidTokenError("undecodable token segment") from error


def _audiences(claims: dict[str, Any]) -> list[Any]:
    aud = claims.get("aud")
    return aud if isinstance(aud, list) else [aud]


def _check_claims(claims: Any, expected_issuer: str) -> uuid.UUID:
    """Reject tokens that are not unexpired end-user tokens for this project."""
    if not isinstance(claims, dict):
        raise InvalidTokenError("claims are not an object")
    if claims.get("iss") != expected_issuer:
        raise InvalidTokenError("unexpected issuer")
    if AUTHENTICATED not in _audiences(claims) or claims.get("role") != AUTHENTICATED:
        raise InvalidTokenError("not an authenticated user token")
    if claims.get("is_anonymous") is True:
        raise InvalidTokenError("anonymous user")
    exp = claims.get("exp")
    if not isinstance(exp, int | float) or isinstance(exp, bool) or exp <= time.time():
        raise InvalidTokenError("missing or past expiry")
    try:
        return uuid.UUID(str(claims.get("sub")))
    except ValueError as error:
        raise InvalidTokenError("subject is not a UUID") from error


class TokenVerifier:
    def __init__(self, settings: SupabaseSettings, client: httpx2.AsyncClient) -> None:
        self._settings = settings
        self._client = client

    async def verify(self, token: str) -> VerifiedUser:
        if len(token) > MAX_TOKEN_LENGTH or not _JWT_SHAPE.fullmatch(token):
            raise InvalidTokenError("malformed token")
        header = _decode_segment(token.split(".")[0])
        if not isinstance(header, dict) or header.get("alg") not in ALLOWED_ALGORITHMS:
            raise InvalidTokenError("unsupported signing algorithm")
        subject = _check_claims(_decode_segment(token.split(".")[1]), self._settings.jwt_issuer)

        try:
            response = await self._client.get(
                f"{self._settings.url}/auth/v1/user",
                headers={
                    "apikey": self._settings.publishable_key,
                    "Authorization": f"Bearer {token}",
                },
                timeout=PROVIDER_TIMEOUT,
                follow_redirects=False,
            )
        except httpx2.HTTPError as error:
            raise AuthUnavailableError("auth provider request failed") from error

        if response.status_code in (400, 401, 403):
            raise InvalidTokenError("rejected by auth provider")
        if response.status_code != 200:
            raise AuthUnavailableError(f"auth provider returned {response.status_code}")
        try:
            user = response.json()
        except ValueError as error:
            raise AuthUnavailableError("auth provider returned invalid JSON") from error
        if not isinstance(user, dict):
            raise AuthUnavailableError("auth provider returned an unexpected body")
        if str(user.get("id")) != str(subject) or user.get("aud") != AUTHENTICATED:
            raise InvalidTokenError("provider identity does not match token")
        if user.get("is_anonymous") is True:
            raise InvalidTokenError("anonymous user")
        return VerifiedUser(user_id=subject, access_token=token)


_BEARER_CHALLENGE = 'Bearer realm="api"'


def _unauthorized(code: str, message: str, *, invalid_token: bool) -> ApiError:
    challenge = (
        f'{_BEARER_CHALLENGE}, error="invalid_token"' if invalid_token else _BEARER_CHALLENGE
    )
    return ApiError(401, code, message, headers={"WWW-Authenticate": challenge})


async def require_user(request: Request) -> VerifiedUser:
    """FastAPI dependency: the verified user for this request, or an API error."""
    verifier: TokenVerifier | None = getattr(request.app.state, "token_verifier", None)
    if verifier is None:
        raise ApiError(503, "auth_not_configured", "Authentication is not configured.")

    header = request.headers.get("authorization")
    if not header:
        raise _unauthorized("missing_token", "Authentication is required.", invalid_token=False)
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise _unauthorized("invalid_token", "Use a Bearer access token.", invalid_token=True)

    try:
        return await verifier.verify(token.strip())
    except InvalidTokenError as error:
        raise _unauthorized(
            "invalid_token", "The access token is invalid or expired.", invalid_token=True
        ) from error
    except AuthUnavailableError as error:
        raise ApiError(
            503, "auth_unavailable", "Authentication is temporarily unavailable."
        ) from error


CurrentUser = Annotated[VerifiedUser, Depends(require_user)]
