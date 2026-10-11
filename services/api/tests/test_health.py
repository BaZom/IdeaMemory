import socket
from typing import NoReturn

import pytest
from fastapi.testclient import TestClient

from app.main import create_app

ALLOWED = "http://localhost:3000"


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app([ALLOWED]))


def test_health_returns_exact_contract(client: TestClient) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == {"status": "ok"}


def test_health_makes_no_network_connections(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def refuse(*_args: object, **_kwargs: object) -> NoReturn:
        raise AssertionError("health check attempted a network call")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "create_connection", refuse)
    monkeypatch.setattr(socket, "getaddrinfo", refuse)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_cors_preflight_allows_configured_origin(client: TestClient) -> None:
    response = client.options(
        "/health",
        headers={"Origin": ALLOWED, "Access-Control-Request-Method": "GET"},
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == ALLOWED


@pytest.mark.parametrize(
    "origin",
    ["http://evil.example", "http://localhost:3001", "https://localhost:3000", "null"],
)
def test_cors_does_not_grant_unrelated_origin(client: TestClient, origin: str) -> None:
    response = client.get("/health", headers={"Origin": origin})

    assert "access-control-allow-origin" not in response.headers
