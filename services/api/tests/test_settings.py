import pytest

from app.settings import allowed_origins_from_env, parse_allowed_origins


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
