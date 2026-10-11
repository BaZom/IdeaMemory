"""The migrated idea schema enforces ownership and integrity for direct Data API
callers, independently of the API."""

import uuid
from typing import Any

import httpx2
import pytest
from support import Stack, StackUser, query_sql, run_sql

pytestmark = pytest.mark.integration


def rest(stack: Stack, path: str) -> str:
    return f"{stack.url}/rest/v1/{path}"


def new_idea(http: httpx2.Client, stack: Stack, user: StackUser, **fields: Any) -> dict[str, Any]:
    response = http.post(
        rest(stack, "rpc/create_idea"),
        headers=user.headers(stack),
        json={"p_title": "Untitled", **fields},
    )
    assert response.status_code == 200, response.text
    idea: dict[str, Any] = response.json()
    return idea


def stored_idea(stack: Stack, idea_id: str) -> dict[str, Any] | None:
    rows = query_sql(stack, f"select * from public.ideas where id = '{idea_id}'")
    return rows[0] if rows else None


def stored_sources(stack: Stack, idea_id: str) -> list[dict[str, Any]]:
    return query_sql(stack, f"select * from public.sources where idea_id = '{idea_id}'")


@pytest.fixture
def a_idea(http: httpx2.Client, stack: Stack, user_a: StackUser) -> dict[str, Any]:
    return new_idea(http, stack, user_a, p_title="A private", p_original_text="A source")


def test_create_stores_owner_and_exact_source(
    stack: Stack, user_a: StackUser, a_idea: dict[str, Any]
) -> None:
    assert "owner_id" not in a_idea
    stored = stored_idea(stack, a_idea["id"])
    assert stored is not None
    assert stored["owner_id"] == user_a.user_id
    [source] = stored_sources(stack, a_idea["id"])
    assert source["original_text"] == "A source"
    assert source["owner_id"] == user_a.user_id


def test_invalid_source_rolls_back_the_whole_create(
    http: httpx2.Client, stack: Stack, user_a: StackUser
) -> None:
    title = f"rollback-{uuid.uuid4()}"

    response = http.post(
        rest(stack, "rpc/create_idea"),
        headers=user_a.headers(stack),
        json={"p_title": title, "p_original_text": "   "},
    )

    assert response.status_code == 400
    assert query_sql(stack, f"select id from public.ideas where title = '{title}'") == []


def test_other_user_cannot_read_update_or_delete(
    http: httpx2.Client, stack: Stack, user_b: StackUser, a_idea: dict[str, Any]
) -> None:
    headers = {**user_b.headers(stack), "Prefer": "return=representation"}
    target = {"id": f"eq.{a_idea['id']}"}

    read = http.get(rest(stack, "ideas"), headers=headers, params=target)
    sources = http.get(
        rest(stack, "sources"), headers=headers, params={"idea_id": f"eq.{a_idea['id']}"}
    )
    listed = http.post(rest(stack, "rpc/list_ideas"), headers=headers, json={"p_limit": 100})
    updated = http.patch(rest(stack, "ideas"), headers=headers, params=target, json={"title": "B"})
    deleted = http.delete(rest(stack, "ideas"), headers=headers, params=target)

    assert read.json() == sources.json() == updated.json() == deleted.json() == []
    assert a_idea["id"] not in listed.text
    stored = stored_idea(stack, a_idea["id"])
    assert stored is not None
    assert stored["title"] == "A private"


def test_source_cannot_be_attached_to_another_users_idea(
    http: httpx2.Client, stack: Stack, user_b: StackUser, a_idea: dict[str, Any]
) -> None:
    response = http.post(
        rest(stack, "sources"),
        headers=user_b.headers(stack),
        json={"idea_id": a_idea["id"], "kind": "text", "original_text": "planted"},
    )

    assert response.status_code == 409  # composite (idea, owner) foreign key
    assert len(stored_sources(stack, a_idea["id"])) == 1


@pytest.mark.parametrize(
    "body",
    [
        {"title": "forged", "owner_id": "A"},
        {"title": "forged", "id": "11111111-1111-4111-8111-111111111111"},
        {"title": "forged", "created_at": "2000-01-01T00:00:00Z"},
    ],
)
def test_server_fields_cannot_be_chosen_on_insert(
    http: httpx2.Client, stack: Stack, user_a: StackUser, user_b: StackUser, body: dict[str, Any]
) -> None:
    filled = {k: user_a.user_id if v == "A" else v for k, v in body.items()}

    response = http.post(rest(stack, "ideas"), headers=user_b.headers(stack), json=filled)

    assert response.status_code == 403


@pytest.mark.parametrize("change", [{"owner_id": "B"}, {"created_at": "2000-01-01T00:00:00Z"}])
def test_owner_and_creation_time_cannot_be_changed(
    http: httpx2.Client,
    stack: Stack,
    user_a: StackUser,
    user_b: StackUser,
    a_idea: dict[str, Any],
    change: dict[str, Any],
) -> None:
    filled = {k: user_b.user_id if v == "B" else v for k, v in change.items()}

    response = http.patch(
        rest(stack, "ideas"),
        headers=user_a.headers(stack),
        params={"id": f"eq.{a_idea['id']}"},
        json=filled,
    )

    assert response.status_code == 403
    stored = stored_idea(stack, a_idea["id"])
    assert stored is not None
    assert stored["owner_id"] == user_a.user_id
    with pytest.raises(Exception, match="returned non-zero exit status"):
        run_sql(
            stack,
            f"update public.ideas set owner_id = '{user_b.user_id}' where id = '{a_idea['id']}'",
        )


@pytest.mark.parametrize("method", ["PATCH", "DELETE"])
def test_sources_are_immutable_for_their_owner(
    http: httpx2.Client, stack: Stack, user_a: StackUser, a_idea: dict[str, Any], method: str
) -> None:
    response = http.request(
        method,
        rest(stack, "sources"),
        headers=user_a.headers(stack),
        params={"idea_id": f"eq.{a_idea['id']}"},
        json={"original_text": "rewritten"} if method == "PATCH" else None,
    )

    assert response.status_code == 403
    [source] = stored_sources(stack, a_idea["id"])
    assert source["original_text"] == "A source"


def test_deleting_an_idea_deletes_its_sources(
    http: httpx2.Client, stack: Stack, user_a: StackUser, a_idea: dict[str, Any]
) -> None:
    http.delete(
        rest(stack, "ideas"), headers=user_a.headers(stack), params={"id": f"eq.{a_idea['id']}"}
    )

    assert stored_idea(stack, a_idea["id"]) is None
    assert stored_sources(stack, a_idea["id"]) == []


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("GET", "ideas", None),
        ("POST", "ideas", {"title": "anon"}),
        ("GET", "sources", None),
        ("POST", "rpc/create_idea", {"p_title": "anon"}),
        ("POST", "rpc/list_ideas", {"p_limit": 10}),
    ],
)
def test_anonymous_callers_have_no_access(
    http: httpx2.Client,
    stack: Stack,
    a_idea: dict[str, Any],
    method: str,
    path: str,
    body: dict[str, Any] | None,
) -> None:
    response = http.request(method, rest(stack, path), headers=stack.public_headers(), json=body)

    assert response.status_code in (401, 403)
    assert a_idea["id"] not in response.text
