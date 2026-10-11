"""Process configuration read from environment variables."""

import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from urllib.parse import urlsplit

ALLOWED_ORIGINS_ENV = "ALLOWED_ORIGINS"


def parse_allowed_origins(raw: str | None) -> list[str]:
    """Parse a comma-separated CORS allowlist of exact browser origins.

    An unset or blank value allows no cross-origin access. Wildcards, paths and
    non-HTTP schemes are rejected so a misconfiguration fails at startup instead
    of silently widening access.
    """
    if raw is None or not raw.strip():
        return []

    origins: list[str] = []
    for entry in raw.split(","):
        origin = entry.strip()
        if not origin:
            continue
        if "*" in origin:
            raise ValueError(f"{ALLOWED_ORIGINS_ENV} must list explicit origins, not wildcards")
        parts = urlsplit(origin)
        if (
            parts.scheme not in ("http", "https")
            or not parts.hostname
            or parts.path
            or parts.query
            or parts.fragment
            or parts.username
            or parts.password
        ):
            raise ValueError(
                f"{ALLOWED_ORIGINS_ENV} entry {origin!r} is not an origin like http://localhost:3000"
            )
        origins.append(origin)
    return origins


def allowed_origins_from_env() -> list[str]:
    return parse_allowed_origins(os.environ.get(ALLOWED_ORIGINS_ENV))


SUPABASE_URL_ENV = "SUPABASE_URL"
SUPABASE_PUBLISHABLE_KEY_ENV = "SUPABASE_PUBLISHABLE_KEY"
SUPABASE_JWT_ISSUER_ENV = "SUPABASE_JWT_ISSUER"
_AUTH_ENVS = (SUPABASE_URL_ENV, SUPABASE_PUBLISHABLE_KEY_ENV, SUPABASE_JWT_ISSUER_ENV)
_LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


@dataclass(frozen=True)
class SupabaseSettings:
    """Server-side Supabase settings for verifying users and acting as them.

    Only the public project key is configured here; privileged keys never reach
    the request path.
    """

    url: str
    publishable_key: str = field(repr=False)
    jwt_issuer: str


def _parse_service_url(name: str, raw: str, *, allow_path: bool) -> str:
    value = raw.strip().rstrip("/")
    parts = urlsplit(value)
    if (
        parts.scheme not in ("http", "https")
        or not parts.hostname
        or parts.query
        or parts.fragment
        or parts.username
        or parts.password
        or (parts.path and not allow_path)
    ):
        raise ValueError(f"{name} {value!r} is not a valid http(s) URL")
    if parts.scheme == "http" and parts.hostname not in _LOOPBACK_HOSTS:
        raise ValueError(f"{name} must use https unless it points at this machine")
    return value


def parse_supabase_settings(env: Mapping[str, str]) -> SupabaseSettings | None:
    """Return Supabase settings, or None when none are configured.

    Partial or invalid configuration raises so a typo fails at startup instead
    of silently disabling authentication.
    """
    values = {name: env.get(name, "").strip() for name in _AUTH_ENVS}
    if not any(values.values()):
        return None
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise ValueError(f"Incomplete Supabase configuration; missing {', '.join(missing)}")
    return SupabaseSettings(
        url=_parse_service_url(SUPABASE_URL_ENV, values[SUPABASE_URL_ENV], allow_path=False),
        publishable_key=values[SUPABASE_PUBLISHABLE_KEY_ENV],
        jwt_issuer=_parse_service_url(
            SUPABASE_JWT_ISSUER_ENV, values[SUPABASE_JWT_ISSUER_ENV], allow_path=True
        ),
    )


def supabase_settings_from_env() -> SupabaseSettings | None:
    return parse_supabase_settings(os.environ)
