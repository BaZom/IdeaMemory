"""T002-AC7: private Storage objects are reachable only by their owner."""

import uuid
from collections.abc import AsyncIterator
from typing import Any

import httpx2
import pytest
from fastapi import APIRouter, FastAPI
from fastapi.responses import Response
from support import Stack, StackUser, running_client

from app.main import create_app
from app.supabase_user import UserSupabase

pytestmark = pytest.mark.integration

CONTENT = b"a-private-object"


def storage(stack: Stack, path: str) -> str:
    return f"{stack.url}/storage/v1/{path}"


def upload(
    http: httpx2.Client,
    stack: Stack,
    headers: dict[str, str],
    bucket: str,
    path: str,
    content: bytes,
    *,
    upsert: bool = False,
) -> httpx2.Response:
    return http.post(
        storage(stack, f"object/{bucket}/{path}"),
        headers={
            **headers,
            "Content-Type": "text/plain",
            "x-upsert": "true" if upsert else "false",
        },
        content=content,
    )


def download(
    http: httpx2.Client, stack: Stack, headers: dict[str, str], bucket: str, path: str
) -> httpx2.Response:
    return http.get(storage(stack, f"object/authenticated/{bucket}/{path}"), headers=headers)


def listing(
    http: httpx2.Client, stack: Stack, headers: dict[str, str], bucket: str, prefix: str
) -> httpx2.Response:
    return http.post(
        storage(stack, f"object/list/{bucket}"), headers=headers, json={"prefix": prefix}
    )


def stored_content(http: httpx2.Client, stack: Stack, bucket: str, path: str) -> bytes:
    """What is really stored (fixture privilege, never used by code under test)."""
    response = download(http, stack, stack.admin_headers(), bucket, path)
    assert response.status_code == 200
    return response.content


@pytest.fixture
def a_object(http: httpx2.Client, stack: Stack, fixture_bucket: str, user_a: StackUser) -> str:
    path = f"{user_a.user_id}/{uuid.uuid4().hex}.txt"
    response = upload(http, stack, user_a.headers(stack), fixture_bucket, path, CONTENT)
    assert response.status_code == 200, response.text
    return path


def test_owner_reads_lists_and_signs_own_object(
    http: httpx2.Client, stack: Stack, fixture_bucket: str, user_a: StackUser, a_object: str
) -> None:
    assert download(http, stack, user_a.headers(stack), fixture_bucket, a_object).content == CONTENT

    names = [
        o["name"]
        for o in listing(http, stack, user_a.headers(stack), fixture_bucket, user_a.user_id).json()
    ]
    assert a_object.split("/")[1] in names

    signed = http.post(
        storage(stack, f"object/sign/{fixture_bucket}/{a_object}"),
        headers=user_a.headers(stack),
        json={"expiresIn": 60},
    )
    assert signed.status_code == 200
    # A signed URL is a bearer capability: it works without any credentials.
    fetched = http.get(f"{stack.url}/storage/v1{signed.json()['signedURL']}")
    assert fetched.content == CONTENT


def test_other_user_cannot_read_list_or_sign(
    http: httpx2.Client,
    stack: Stack,
    fixture_bucket: str,
    user_a: StackUser,
    user_b: StackUser,
    a_object: str,
) -> None:
    b = user_b.headers(stack)

    read = download(http, stack, b, fixture_bucket, a_object)
    assert read.status_code in (400, 403, 404)
    assert CONTENT not in read.content

    listed = listing(http, stack, b, fixture_bucket, user_a.user_id)
    assert listed.status_code == 200
    assert listed.json() == []

    signed = http.post(
        storage(stack, f"object/sign/{fixture_bucket}/{a_object}"),
        headers=b,
        json={"expiresIn": 60},
    )
    assert signed.status_code in (400, 403, 404)
    assert "signedURL" not in signed.text


def test_other_user_cannot_overwrite_plant_or_delete(
    http: httpx2.Client,
    stack: Stack,
    fixture_bucket: str,
    user_a: StackUser,
    user_b: StackUser,
    a_object: str,
) -> None:
    b = user_b.headers(stack)

    overwrite = upload(http, stack, b, fixture_bucket, a_object, b"evil", upsert=True)
    assert overwrite.status_code in (400, 403)

    planted = upload(http, stack, b, fixture_bucket, f"{user_a.user_id}/planted.txt", b"evil")
    assert planted.status_code in (400, 403)

    deleted = http.request(
        "DELETE",
        storage(stack, f"object/{fixture_bucket}"),
        headers=b,
        json={"prefixes": [a_object]},
    )
    assert deleted.json() == []

    assert stored_content(http, stack, fixture_bucket, a_object) == CONTENT
    assert download(
        http, stack, stack.admin_headers(), fixture_bucket, f"{user_a.user_id}/planted.txt"
    ).status_code in (400, 404)


def test_anonymous_callers_have_no_access(
    http: httpx2.Client, stack: Stack, fixture_bucket: str, user_a: StackUser, a_object: str
) -> None:
    anon = stack.public_headers()

    assert CONTENT not in download(http, stack, anon, fixture_bucket, a_object).content
    assert http.get(storage(stack, f"object/public/{fixture_bucket}/{a_object}")).status_code in (
        400,
        404,
    )
    listed = listing(http, stack, anon, fixture_bucket, user_a.user_id)
    assert listed.status_code != 200 or listed.json() == []
    assert upload(
        http, stack, anon, fixture_bucket, f"{user_a.user_id}/anon.txt", b"x"
    ).status_code in (400, 401, 403)


def test_owner_deletes_own_object(
    http: httpx2.Client, stack: Stack, fixture_bucket: str, user_a: StackUser, a_object: str
) -> None:
    deleted = http.request(
        "DELETE",
        storage(stack, f"object/{fixture_bucket}"),
        headers=user_a.headers(stack),
        json={"prefixes": [a_object]},
    )

    assert [o["name"] for o in deleted.json()] == [a_object]
    assert download(http, stack, user_a.headers(stack), fixture_bucket, a_object).status_code in (
        400,
        404,
    )


# --- through the API's user-scoped boundary (test-only routes) ---------------


def _test_app(stack: Stack, bucket: str) -> FastAPI:
    application = create_app([], stack.settings)
    router = APIRouter()

    @router.put("/test-only/objects/{path:path}")
    async def put_object(path: str, db: UserSupabase, body: dict[str, Any]) -> Any:
        response = await db.storage(
            "POST",
            f"object/{bucket}/{path}",
            content=str(body["text"]).encode(),
            headers={"Content-Type": "text/plain"},
        )
        return {"status": response.status_code}

    @router.get("/test-only/objects/{path:path}")
    async def get_object(path: str, db: UserSupabase) -> Response:
        response = await db.storage("GET", f"object/authenticated/{bucket}/{path}")
        return Response(content=response.content, status_code=response.status_code)

    application.include_router(router)
    return application


@pytest.fixture
async def boundary(stack: Stack, fixture_bucket: str) -> AsyncIterator[httpx2.AsyncClient]:
    async with running_client(_test_app(stack, fixture_bucket)) as client:
        yield client


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.mark.anyio
async def test_backend_boundary_stores_and_reads_only_as_the_caller(
    boundary: httpx2.AsyncClient, user_a: StackUser, user_b: StackUser
) -> None:
    path = f"{user_a.user_id}/{uuid.uuid4().hex}.txt"
    a = {"Authorization": f"Bearer {user_a.access_token}"}
    b = {"Authorization": f"Bearer {user_b.access_token}"}

    stored = await boundary.put(f"/test-only/objects/{path}", headers=a, json={"text": "via-api"})
    assert stored.json() == {"status": 200}

    assert (await boundary.get(f"/test-only/objects/{path}", headers=a)).content == b"via-api"
    as_b = await boundary.get(f"/test-only/objects/{path}", headers=b)
    assert as_b.status_code in (400, 403, 404)
    assert b"via-api" not in as_b.content

    planted = await boundary.put(f"/test-only/objects/{path}", headers=b, json={"text": "evil"})
    assert planted.json()["status"] in (400, 403)
