"""T002-AC6: row ownership enforced by the database for direct Data API calls
and for the API's user-scoped boundary."""

from collections.abc import AsyncIterator
from typing import Any

import httpx2
import pytest
from fastapi import APIRouter, FastAPI
from support import Stack, StackUser, running_client

from app.main import create_app
from app.supabase_user import UserSupabase

pytestmark = pytest.mark.integration


def rest(http: httpx2.Client, stack: Stack, table: str) -> str:
    return f"{stack.url}/rest/v1/{table}"


def insert(
    http: httpx2.Client, stack: Stack, table: str, user: StackUser, body: dict[str, Any]
) -> httpx2.Response:
    return http.post(
        rest(http, stack, table),
        headers={**user.headers(stack), "Prefer": "return=representation"},
        json=body,
    )


def rows_visible_to(
    http: httpx2.Client, stack: Stack, table: str, user: StackUser, **filters: str
) -> list[dict[str, Any]]:
    response = http.get(rest(http, stack, table), headers=user.headers(stack), params=filters)
    assert response.status_code == 200
    rows: list[dict[str, Any]] = response.json()
    return rows


def owner_view(http: httpx2.Client, stack: Stack, table: str, row_id: str) -> dict[str, Any]:
    """The row as the database stores it (fixture privilege, never used by code under test)."""
    response = http.get(
        rest(http, stack, table),
        headers=stack.admin_headers(),
        params={"id": f"eq.{row_id}"},
    )
    assert response.status_code == 200
    [row] = response.json()
    assert isinstance(row, dict)
    return row


@pytest.fixture
def a_row(
    http: httpx2.Client, stack: Stack, fixture_table: str, user_a: StackUser
) -> dict[str, Any]:
    response = insert(http, stack, fixture_table, user_a, {"note": "a-private"})
    assert response.status_code == 201
    [row] = response.json()
    assert row["owner_id"] == user_a.user_id
    assert isinstance(row, dict)
    return row


def test_owner_reads_own_row(
    http: httpx2.Client, stack: Stack, fixture_table: str, user_a: StackUser, a_row: dict[str, Any]
) -> None:
    rows = rows_visible_to(http, stack, fixture_table, user_a, id=f"eq.{a_row['id']}")
    assert rows == [a_row]


def test_other_user_cannot_read(
    http: httpx2.Client,
    stack: Stack,
    fixture_table: str,
    user_b: StackUser,
    a_row: dict[str, Any],
) -> None:
    assert rows_visible_to(http, stack, fixture_table, user_b, id=f"eq.{a_row['id']}") == []
    assert all(
        r["owner_id"] == user_b.user_id for r in rows_visible_to(http, stack, fixture_table, user_b)
    )


def test_other_user_cannot_update(
    http: httpx2.Client,
    stack: Stack,
    fixture_table: str,
    user_b: StackUser,
    a_row: dict[str, Any],
) -> None:
    response = http.patch(
        rest(http, stack, fixture_table),
        headers={**user_b.headers(stack), "Prefer": "return=representation"},
        params={"id": f"eq.{a_row['id']}"},
        json={"note": "b-was-here"},
    )

    assert response.status_code == 200
    assert response.json() == []  # filtered out by RLS: nothing matched
    assert owner_view(http, stack, fixture_table, a_row["id"])["note"] == "a-private"


def test_other_user_cannot_delete(
    http: httpx2.Client,
    stack: Stack,
    fixture_table: str,
    user_b: StackUser,
    a_row: dict[str, Any],
) -> None:
    response = http.delete(
        rest(http, stack, fixture_table),
        headers={**user_b.headers(stack), "Prefer": "return=representation"},
        params={"id": f"eq.{a_row['id']}"},
    )

    assert response.json() == []
    assert owner_view(http, stack, fixture_table, a_row["id"])["owner_id"] == a_row["owner_id"]


def test_forged_owner_on_insert_is_refused(
    http: httpx2.Client,
    stack: Stack,
    fixture_table: str,
    user_a: StackUser,
    user_b: StackUser,
) -> None:
    response = insert(
        http, stack, fixture_table, user_b, {"note": "planted", "owner_id": user_a.user_id}
    )

    assert response.status_code == 403
    assert rows_visible_to(http, stack, fixture_table, user_a, note="eq.planted") == []


def test_owner_cannot_give_a_row_away(
    http: httpx2.Client,
    stack: Stack,
    fixture_table: str,
    user_a: StackUser,
    user_b: StackUser,
    a_row: dict[str, Any],
) -> None:
    response = http.patch(
        rest(http, stack, fixture_table),
        headers=user_a.headers(stack),
        params={"id": f"eq.{a_row['id']}"},
        json={"owner_id": user_b.user_id},
    )

    assert response.status_code == 403
    assert owner_view(http, stack, fixture_table, a_row["id"])["owner_id"] == user_a.user_id


def test_owner_updates_and_deletes_own_row(
    http: httpx2.Client, stack: Stack, fixture_table: str, user_a: StackUser, a_row: dict[str, Any]
) -> None:
    updated = http.patch(
        rest(http, stack, fixture_table),
        headers={**user_a.headers(stack), "Prefer": "return=representation"},
        params={"id": f"eq.{a_row['id']}"},
        json={"note": "a-edited"},
    )
    assert [row["note"] for row in updated.json()] == ["a-edited"]

    deleted = http.delete(
        rest(http, stack, fixture_table),
        headers={**user_a.headers(stack), "Prefer": "return=representation"},
        params={"id": f"eq.{a_row['id']}"},
    )
    assert [row["id"] for row in deleted.json()] == [a_row["id"]]


@pytest.mark.parametrize("method", ["GET", "POST", "PATCH", "DELETE"])
def test_anonymous_callers_have_no_access(
    http: httpx2.Client, stack: Stack, fixture_table: str, a_row: dict[str, Any], method: str
) -> None:
    response = http.request(
        method,
        rest(http, stack, fixture_table),
        headers={**stack.public_headers(), "Prefer": "return=representation"},
        params={} if method == "POST" else {"id": f"eq.{a_row['id']}"},
        json=None if method in ("GET", "DELETE") else {"note": "anon"},
    )

    assert response.status_code in (401, 403)
    assert a_row["id"] not in response.text
    assert owner_view(http, stack, fixture_table, a_row["id"])["note"] == "a-private"


# --- through the API's user-scoped boundary (test-only routes) ---------------


def _test_app(stack: Stack, table: str) -> FastAPI:
    """The shipped app plus routes that exist only in this test."""
    application = create_app([], stack.settings)
    router = APIRouter()

    @router.get("/test-only/rows")
    async def list_rows(db: UserSupabase) -> Any:
        response = await db.rest("GET", table)
        return response.json()

    @router.post("/test-only/rows")
    async def add_row(db: UserSupabase, body: dict[str, Any]) -> Any:
        response = await db.rest(
            "POST", table, json=body, headers={"Prefer": "return=representation"}
        )
        return {"status": response.status_code, "body": response.json()}

    application.include_router(router)
    return application


@pytest.fixture
async def boundary(stack: Stack, fixture_table: str) -> AsyncIterator[httpx2.AsyncClient]:
    async with running_client(_test_app(stack, fixture_table)) as client:
        yield client


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.mark.anyio
async def test_backend_boundary_acts_only_as_the_caller(
    boundary: httpx2.AsyncClient, user_a: StackUser, user_b: StackUser
) -> None:
    def as_user(user: StackUser) -> dict[str, str]:
        return {"Authorization": f"Bearer {user.access_token}"}

    created = await boundary.post(
        "/test-only/rows", headers=as_user(user_a), json={"note": "via-api"}
    )
    assert created.json()["status"] == 201
    row_id = created.json()["body"][0]["id"]

    forged = await boundary.post(
        "/test-only/rows",
        headers=as_user(user_b),
        json={"note": "forged-via-api", "owner_id": user_a.user_id},
    )
    assert forged.json()["status"] == 403

    a_rows = (await boundary.get("/test-only/rows", headers=as_user(user_a))).json()
    b_rows = (await boundary.get("/test-only/rows", headers=as_user(user_b))).json()
    assert row_id in {r["id"] for r in a_rows}
    assert row_id not in {r["id"] for r in b_rows}
    assert all(r["owner_id"] == user_b.user_id for r in b_rows)

    unauthenticated = await boundary.get("/test-only/rows")
    assert unauthenticated.status_code == 401
