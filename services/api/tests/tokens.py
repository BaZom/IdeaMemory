"""Test helper for building JWT-shaped tokens with chosen claims.

Signatures are HMAC-SHA256 with a caller-supplied secret. Unit tests never rely
on the signature (the fake provider decides validity); integration tests use it
to mint deliberately invalid or expired tokens for the real provider to reject.
"""

import base64
import hashlib
import hmac
import json
import time
import uuid
from typing import Any

ISSUER = "http://127.0.0.1:54321/auth/v1"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_token(secret: str = "unit-test-secret", *, alg: str = "ES256", **overrides: Any) -> str:
    """Build a token. `alg` only labels the header: the signature is always
    HMAC-SHA256, so only the fake provider in unit tests treats it as valid."""
    now = int(time.time())
    claims: dict[str, Any] = {
        "iss": ISSUER,
        "aud": "authenticated",
        "role": "authenticated",
        "sub": str(uuid.uuid4()),
        "iat": now,
        "exp": now + 3600,
        "is_anonymous": False,
    }
    for key, value in overrides.items():
        if value is None:
            claims.pop(key, None)
        else:
            claims[key] = value
    header = _b64(json.dumps({"alg": alg, "typ": "JWT"}).encode())
    payload = _b64(json.dumps(claims).encode())
    signature = hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256)
    return f"{header}.{payload}.{_b64(signature.digest())}"


def subject_of(token: str) -> str:
    payload = token.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    return str(claims["sub"])
