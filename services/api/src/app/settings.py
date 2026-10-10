"""Process configuration read from environment variables."""

import os
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
