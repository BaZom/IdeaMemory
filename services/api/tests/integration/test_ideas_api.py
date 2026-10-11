"""`/api/v1/ideas` against the real migrated stack, acting only as the caller."""

import uuid
from collections.abc import AsyncIterator
from typing import Any

import httpx2
import pytest
from support import Stack, StackUser, query_sql, run_sql, running_client, unique_email

from app.main import create_app

pytestmark = [pytest.mark.integration, pytest.mark.anyio]


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
async def api(stack: Stack) -> AsyncIterator[httpx2.AsyncClient]:
    async with running_client(create_app([], stack.settings)) as client:
        yield client


def as_user(user: StackUser) -> dict[str, str]:
    return {"Authorization": f"Bearer {user.access_token}"}


async def created(api: httpx2.AsyncClient, user: StackUser, **body: Any) -> dict[str, Any]:
    response = await api.post(
        "/api/v1/ideas", headers=as_user(user), json={"title": "Idea", **body}
    )
    assert response.status_code == 201, response.text
    idea: dict[str, Any] = response.json()
    return idea


async def all_ids(api: httpx2.AsyncClient, user: StackUser, limit: int) -> list[str]:
    ids: list[str] = []
    params: dict[str, str | int] = {"limit": limit}
    while True:
        page = (await api.get("/api/v1/ideas", headers=as_user(user), params=params)).json()
        ids += [item["id"] for item in page["items"]]
        if page["next_cursor"] is None:
            return ids
        params["cursor"] = page["next_cursor"]


async def test_new_signed_up_account_saves_a_title_only_idea(
    api: httpx2.AsyncClient, http: httpx2.Client, stack: Stack, provisioned: list[str]
) -> None:
    signup = http.post(
        f"{stack.url}/auth/v1/signup",
        headers=stack.public_headers(),
        json={
            "email": unique_email("signup").replace("@example.test", "@users.invalid"),
            "password": "Correct-horse-battery-1",
        },
    )
    assert signup.status_code == 200
    provisioned.append(signup.json()["user"]["id"])
    headers = {"Authorization": f"Bearer {signup.json()['access_token']}"}

    response = await api.post("/api/v1/ideas", headers=headers, json={"title": " First "})

    assert response.status_code == 201
    idea = response.json()
    assert idea["title"] == "First"
    assert idea["sources"] == []
    assert response.headers["cache-control"] == "no-store"
    listed = (await api.get("/api/v1/ideas", headers=headers)).json()
    assert [item["id"] for item in listed["items"]] == [idea["id"]]


async def test_create_edit_and_delete(
    api: httpx2.AsyncClient, stack: Stack, user_a: StackUser
) -> None:
    original = "  Exact\r\n\ttext \U0001f35c  "
    idea = await created(
        api,
        user_a,
        title=" Ramen ",
        description="Broth",
        category="food",
        tags=["Noodles", "noodles"],
        original_text=original,
    )
    url = f"/api/v1/ideas/{idea['id']}"
    assert idea["tags"] == ["Noodles"]
    assert idea["sources"][0]["original_text"] == original
    assert (await api.get(url, headers=as_user(user_a))).json() == idea

    edited = await api.patch(
        url, headers=as_user(user_a), json={"title": "Ramen bar", "description": None}
    )
    assert edited.status_code == 200
    assert edited.json()["title"] == "Ramen bar"
    assert edited.json()["description"] is None
    assert edited.json()["category"] == "food"
    assert edited.json()["sources"] == idea["sources"]  # original text never changes
    assert edited.json()["updated_at"] >= idea["updated_at"]

    assert (await api.delete(url, headers=as_user(user_a))).status_code == 204
    assert (await api.delete(url, headers=as_user(user_a))).status_code == 404
    assert (await api.get(url, headers=as_user(user_a))).status_code == 404
    sources = query_sql(
        stack, f"select count(*) as n from public.sources where idea_id = '{idea['id']}'"
    )
    assert sources == [{"n": 0}]


async def test_other_users_idea_is_indistinguishable_from_a_missing_one(
    api: httpx2.AsyncClient, user_a: StackUser, user_b: StackUser
) -> None:
    idea = await created(api, user_a, title="A only", original_text="secret source")
    url = f"/api/v1/ideas/{idea['id']}"

    foreign = await api.get(url, headers=as_user(user_b))
    missing = await api.get(f"/api/v1/ideas/{uuid.uuid4()}", headers=as_user(user_b))
    edit = await api.patch(url, headers=as_user(user_b), json={"title": "B"})
    delete = await api.delete(url, headers=as_user(user_b))

    assert foreign.status_code == missing.status_code == edit.status_code == 404
    assert delete.status_code == 404
    assert foreign.json() == missing.json()
    assert "secret" not in foreign.text
    assert idea["id"] not in await all_ids(api, user_b, 100)
    assert (await api.get(url, headers=as_user(user_a))).json() == idea


async def test_pagination_is_stable_across_equal_timestamps(
    api: httpx2.AsyncClient, stack: Stack, user_b: StackUser
) -> None:
    # One transaction gives every row the same created_at.
    marker = uuid.uuid4().hex[:8]
    run_sql(
        stack,
        "insert into public.ideas (owner_id, title) select"
        f" '{user_b.user_id}', 'same-time-{marker}-' || n from generate_series(1, 7) n",
    )
    rows = query_sql(
        stack,
        "select id::text from public.ideas"
        f" where title like 'same-time-{marker}-%' order by id desc",
    )

    ids = await all_ids(api, user_b, 2)

    expected = [row["id"] for row in rows]
    assert [i for i in ids if i in set(expected)] == expected
    assert len(ids) == len(set(ids))


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/api/v1/ideas"),
        ("POST", "/api/v1/ideas"),
        ("GET", f"/api/v1/ideas/{uuid.uuid4()}"),
        ("PATCH", f"/api/v1/ideas/{uuid.uuid4()}"),
        ("DELETE", f"/api/v1/ideas/{uuid.uuid4()}"),
    ],
)
async def test_every_route_requires_a_valid_token(
    api: httpx2.AsyncClient, method: str, path: str
) -> None:
    missing = await api.request(method, path, json={"title": "x"})
    invalid = await api.request(
        method, path, headers={"Authorization": "Bearer not-a-token"}, json={"title": "x"}
    )

    assert missing.status_code == invalid.status_code == 401
