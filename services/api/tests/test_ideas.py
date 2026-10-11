"""Unit tests for /api/v1/ideas with fake Supabase Auth and Data API servers."""

import logging
import uuid
from collections.abc import AsyncIterator, Callable
from typing import Any

import httpx2
import pytest
from pydantic import ValidationError

from app.errors import MAX_REQUEST_BODY_BYTES
from app.ideas.models import IdeaCreate, IdeaUpdate
from app.main import create_app
from app.settings import SupabaseSettings
from tokens import ISSUER, make_token, subject_of

SETTINGS = SupabaseSettings(
    url="http://127.0.0.1:54321", publishable_key="sb_publishable_test", jwt_issuer=ISSUER
)
ORIGIN = "http://localhost:3000"
SECRET = "Very private idea text"
IDEA_ID = "6f9a4a8e-34a4-4c1e-9d3e-1d6f0f3f6b11"
NOW = "2026-10-11T10:00:00.123456+00:00"
pytestmark = pytest.mark.anyio


def idea_row(**overrides: Any) -> dict[str, Any]:
    return {
        "id": IDEA_ID,
        "title": "Ramen",
        "description": None,
        "notes": None,
        "location": None,
        "category": None,
        "tags": [],
        "created_at": NOW,
        "updated_at": NOW,
        "sources": [],
        **overrides,
    }


class FakeSupabase:
    """Accepts one registered token; Data API answers come from `data`."""

    def __init__(self) -> None:
        self.token = make_token()
        self.data: Callable[[httpx2.Request], httpx2.Response] = lambda _r: httpx2.Response(
            200, json=[]
        )
        self.data_requests: list[httpx2.Request] = []

    def handle(self, request: httpx2.Request) -> httpx2.Response:
        if request.url.path == "/auth/v1/user":
            if request.headers.get("authorization") != f"Bearer {self.token}":
                return httpx2.Response(403, json={"error_code": "bad_jwt"})
            return httpx2.Response(200, json={"id": subject_of(self.token), "aud": "authenticated"})
        self.data_requests.append(request)
        return self.data(request)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def fake() -> FakeSupabase:
    return FakeSupabase()


@pytest.fixture
async def api(fake: FakeSupabase) -> AsyncIterator[httpx2.AsyncClient]:
    application = create_app([ORIGIN], SETTINGS, http_transport=httpx2.MockTransport(fake.handle))
    async with application.router.lifespan_context(application):
        transport = httpx2.ASGITransport(app=application)
        async with httpx2.AsyncClient(transport=transport, base_url="http://testserver") as client:
            yield client


def auth(fake: FakeSupabase) -> dict[str, str]:
    return {"Authorization": f"Bearer {fake.token}"}


# --- validation ----------------------------------------------------------------------


def test_create_normalises_text_and_keeps_original_text_exactly() -> None:
    idea = IdeaCreate.model_validate(
        {
            "title": "　 Ramen \n",
            "description": "  ",
            "location": " Berlin ",
            "tags": [" Food ", "food", "Night"],
            "original_text": "  exact\n\ttext ",
        }
    )

    assert idea.title == "Ramen"
    assert idea.description is None
    assert idea.location == "Berlin"
    assert idea.tags == ["Food", "Night"]
    assert idea.original_text == "  exact\n\ttext "


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"title": " "},
        {"title": "x" * 201},
        {"title": "t", "location": "x" * 301},
        {"title": "t", "category": "music"},
        {"title": "t", "tags": [""]},
        {"title": "t", "tags": [f"t{n}" for n in range(21)]},
        {"title": "t", "original_text": " \n "},
        {"title": "t", "owner_id": str(uuid.uuid4())},
        {"title": 5},
    ],
)
def test_create_rejects_invalid_values(body: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        IdeaCreate.model_validate(body)


@pytest.mark.parametrize(
    "body", [{}, {"title": None}, {"original_text": "x"}, {"owner_id": str(uuid.uuid4())}]
)
def test_update_rejects_empty_immutable_and_unknown_changes(body: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        IdeaUpdate.model_validate(body)


# --- HTTP behavior ---------------------------------------------------------------------


async def test_validation_errors_name_fields_without_echoing_values(
    api: httpx2.AsyncClient, fake: FakeSupabase
) -> None:
    response = await api.post(
        "/api/v1/ideas",
        headers=auth(fake),
        json={"title": SECRET * 20, "category": SECRET, "owner_id": SECRET},
    )

    assert response.status_code == 422
    assert response.headers["cache-control"] == "no-store"
    assert SECRET not in response.text
    fields = {f["field"] for f in response.json()["error"]["fields"]}
    assert fields == {"title", "category", "owner_id"}
    assert fake.data_requests == []


async def test_authentication_is_checked_before_validation(api: httpx2.AsyncClient) -> None:
    response = await api.post("/api/v1/ideas", json={"title": ""})

    assert response.status_code == 401
    assert "fields" not in response.json()["error"]


async def test_create_sends_normalised_values_as_the_caller(
    api: httpx2.AsyncClient, fake: FakeSupabase
) -> None:
    fake.data = lambda _r: httpx2.Response(200, json=idea_row())

    response = await api.post("/api/v1/ideas", headers=auth(fake), json={"title": " Ramen "})

    assert response.status_code == 201
    [request] = fake.data_requests
    assert request.url.path == "/rest/v1/rpc/create_idea"
    assert request.headers["authorization"] == f"Bearer {fake.token}"
    assert httpx2.Response(200, content=request.content).json()["p_title"] == "Ramen"


async def test_detail_edit_and_delete_filter_by_verified_owner(
    api: httpx2.AsyncClient, fake: FakeSupabase
) -> None:
    fake.data = lambda _r: httpx2.Response(200, json=[idea_row()])
    url = f"/api/v1/ideas/{IDEA_ID}"

    assert (await api.get(url, headers=auth(fake))).status_code == 200
    assert (await api.patch(url, headers=auth(fake), json={"title": "x"})).status_code == 200
    assert (await api.delete(url, headers=auth(fake))).status_code == 204

    for request in fake.data_requests:
        assert request.url.params["id"] == f"eq.{IDEA_ID}"
        assert request.url.params["owner_id"] == f"eq.{subject_of(fake.token)}"


async def test_missing_idea_is_404(api: httpx2.AsyncClient, fake: FakeSupabase) -> None:
    url = f"/api/v1/ideas/{IDEA_ID}"

    for method in ("GET", "PATCH", "DELETE"):
        body = {"title": "x"} if method == "PATCH" else None
        response = await api.request(method, url, headers=auth(fake), json=body)
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "idea_not_found"


@pytest.mark.parametrize(
    ("provider", "status"),
    [
        (lambda _r: httpx2.Response(503, text="down"), 503),
        (
            lambda _r: httpx2.Response(
                400, json={"code": "23514", "details": f"Failing row contains ({SECRET})"}
            ),
            422,
        ),
        (lambda _r: httpx2.Response(200, text="not json"), 500),
    ],
)
async def test_provider_failures_are_safe(
    api: httpx2.AsyncClient,
    fake: FakeSupabase,
    caplog: pytest.LogCaptureFixture,
    provider: Callable[[httpx2.Request], httpx2.Response],
    status: int,
) -> None:
    fake.data = provider
    caplog.set_level(logging.DEBUG)

    response = await api.post("/api/v1/ideas", headers=auth(fake), json={"title": SECRET})

    assert response.status_code == status
    assert SECRET not in response.text
    assert SECRET not in caplog.text
    assert fake.token not in caplog.text


async def test_oversized_body_is_413_before_parsing(
    api: httpx2.AsyncClient, fake: FakeSupabase
) -> None:
    async def chunks() -> AsyncIterator[bytes]:
        yield b'{"title": "'
        for _ in range(5):
            yield b"x" * (64 * 1024)
        yield b'"}'

    sized = await api.post(
        "/api/v1/ideas",
        headers={**auth(fake), "Origin": ORIGIN},
        content=b"x" * (MAX_REQUEST_BODY_BYTES + 1),
    )
    chunked = await api.post("/api/v1/ideas", headers=auth(fake), content=chunks())

    assert sized.status_code == chunked.status_code == 413
    assert sized.headers["access-control-allow-origin"] == ORIGIN
    assert fake.data_requests == []


@pytest.mark.parametrize("method", ["POST", "PATCH", "DELETE"])
async def test_cors_preflight_allows_crud_for_configured_origin_only(
    api: httpx2.AsyncClient, method: str
) -> None:
    def preflight(origin: str) -> dict[str, str]:
        return {
            "Origin": origin,
            "Access-Control-Request-Method": method,
            "Access-Control-Request-Headers": "authorization,content-type",
        }

    allowed = await api.options(f"/api/v1/ideas/{IDEA_ID}", headers=preflight(ORIGIN))
    refused = await api.options(f"/api/v1/ideas/{IDEA_ID}", headers=preflight("http://evil.test"))

    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == ORIGIN
    assert refused.status_code == 400
