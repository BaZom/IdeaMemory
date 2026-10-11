import pytest

from app.settings import (
    SupabaseSettings,
    allowed_origins_from_env,
    parse_allowed_origins,
    parse_supabase_settings,
)


@pytest.mark.parametrize("raw", [None, "", "   ", " , "])
def test_unset_or_blank_allows_no_origins(raw: str | None) -> None:
    assert parse_allowed_origins(raw) == []


def test_parses_comma_separated_origins() -> None:
    raw = " http://localhost:3000 , https://app.example:8443,http://192.168.1.20:3000"

    assert parse_allowed_origins(raw) == [
        "http://localhost:3000",
        "https://app.example:8443",
        "http://192.168.1.20:3000",
    ]


@pytest.mark.parametrize(
    "raw",
    [
        "*",
        "http://*.example",
        "localhost:3000",
        "ftp://localhost:3000",
        "http://localhost:3000/",
        "http://localhost:3000/app",
        "http://localhost:3000?x=1",
        "http://user:pass@localhost:3000",
        "http://",
    ],
)
def test_rejects_non_origin_values(raw: str) -> None:
    with pytest.raises(ValueError, match="ALLOWED_ORIGINS"):
        parse_allowed_origins(raw)


def test_reads_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ALLOWED_ORIGINS", "http://localhost:3000")
    assert allowed_origins_from_env() == ["http://localhost:3000"]

    monkeypatch.delenv("ALLOWED_ORIGINS")
    assert allowed_origins_from_env() == []


FULL = {
    "SUPABASE_URL": "http://127.0.0.1:54321",
    "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
    "SUPABASE_JWT_ISSUER": "http://127.0.0.1:54321/auth/v1",
}


def test_supabase_unset_means_not_configured() -> None:
    assert parse_supabase_settings({}) is None
    assert parse_supabase_settings({name: " " for name in FULL}) is None


def test_supabase_full_configuration() -> None:
    settings = parse_supabase_settings({**FULL, "SUPABASE_URL": "http://localhost:54321/"})

    assert settings == SupabaseSettings(
        url="http://localhost:54321",
        publishable_key="sb_publishable_local",
        jwt_issuer="http://127.0.0.1:54321/auth/v1",
    )


def test_supabase_https_allowed_for_remote_hosts() -> None:
    settings = parse_supabase_settings(
        {
            **FULL,
            "SUPABASE_URL": "https://abc.supabase.co",
            "SUPABASE_JWT_ISSUER": "https://abc.supabase.co/auth/v1",
        }
    )

    assert settings is not None
    assert settings.url == "https://abc.supabase.co"


@pytest.mark.parametrize("missing", list(FULL))
def test_supabase_partial_configuration_fails(missing: str) -> None:
    env = {name: value for name, value in FULL.items() if name != missing}

    with pytest.raises(ValueError, match=missing):
        parse_supabase_settings(env)


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("SUPABASE_URL", "http://192.168.1.20:54321"),
        ("SUPABASE_URL", "http://abc.supabase.co"),
        ("SUPABASE_URL", "ftp://127.0.0.1:54321"),
        ("SUPABASE_URL", "http://127.0.0.1:54321/rest"),
        ("SUPABASE_URL", "http://user:pw@127.0.0.1:54321"),
        ("SUPABASE_URL", "127.0.0.1:54321"),
        ("SUPABASE_JWT_ISSUER", "http://abc.supabase.co/auth/v1"),
        ("SUPABASE_JWT_ISSUER", "not a url"),
    ],
)
def test_supabase_invalid_urls_fail(name: str, value: str) -> None:
    with pytest.raises(ValueError, match=name):
        parse_supabase_settings({**FULL, name: value})
