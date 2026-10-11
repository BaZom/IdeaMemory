"""`/api/v1/ideas`: the caller's own ideas.

The owner is always the verified caller. A missing idea and another user's
idea get the same 404.
"""

import base64
import binascii
import json
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from app.auth import CurrentUser
from app.errors import ApiError
from app.ideas import store
from app.ideas.models import Category, Idea, IdeaCreate, IdeaPage, IdeaUpdate
from app.supabase_user import UserSupabase

_CURSOR_VERSION = 1
_CURSOR_MAX_LENGTH = 200


def _no_store(response: Response) -> None:
    response.headers["Cache-Control"] = "no-store"


router = APIRouter(prefix="/api/v1/ideas", dependencies=[Depends(_no_store)])


def _not_found() -> ApiError:
    return ApiError(404, "idea_not_found", "This idea does not exist.")


def encode_cursor(created_at: datetime, idea_id: uuid.UUID) -> str:
    state = {"v": _CURSOR_VERSION, "t": created_at.isoformat(), "id": str(idea_id)}
    raw = json.dumps(state, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    invalid = ApiError(422, "invalid_cursor", "The page cursor is not valid.")
    if len(cursor) > _CURSOR_MAX_LENGTH:
        raise invalid
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4))
        state = json.loads(raw)
        if (
            not isinstance(state, dict)
            or set(state) != {"v", "t", "id"}
            or state["v"] != _CURSOR_VERSION
            or not isinstance(state["t"], str)
            or not isinstance(state["id"], str)
        ):
            raise ValueError("unsupported cursor")
        created_at = datetime.fromisoformat(state["t"])
        idea_id = uuid.UUID(state["id"])
    except (binascii.Error, ValueError, UnicodeDecodeError):
        raise invalid from None
    if created_at.tzinfo is None:
        raise invalid
    return created_at, idea_id


@router.post("", status_code=201)
async def create_idea(body: IdeaCreate, db: UserSupabase) -> Idea:
    """Saves a new idea and its optional original text."""
    return await store.create_idea(db, body)


@router.get("")
async def list_ideas(
    db: UserSupabase,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
    category: Annotated[Category | None, Query()] = None,
) -> IdeaPage:
    """The caller's ideas, newest first, optionally of one category. Pass
    `next_cursor` (with the same category) to get the next page."""
    before = decode_cursor(cursor) if cursor is not None else None
    rows = await store.list_ideas(db, limit + 1, before, category)
    items = rows[:limit]
    next_cursor = encode_cursor(items[-1].created_at, items[-1].id) if len(rows) > limit else None
    return IdeaPage(items=items, next_cursor=next_cursor)


@router.get("/{idea_id}")
async def get_idea(idea_id: uuid.UUID, user: CurrentUser, db: UserSupabase) -> Idea:
    idea = await store.get_idea(db, user.user_id, idea_id)
    if idea is None:
        raise _not_found()
    return idea


@router.patch("/{idea_id}")
async def update_idea(
    idea_id: uuid.UUID, body: IdeaUpdate, user: CurrentUser, db: UserSupabase
) -> Idea:
    """Changes the given fields; the last save wins."""
    idea = await store.update_idea(db, user.user_id, idea_id, body.changes())
    if idea is None:
        raise _not_found()
    return idea


@router.delete("/{idea_id}", status_code=204)
async def delete_idea(idea_id: uuid.UUID, user: CurrentUser, db: UserSupabase) -> None:
    """Deletes the idea and its sources."""
    if not await store.delete_idea(db, user.user_id, idea_id):
        raise _not_found()
