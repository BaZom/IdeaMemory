"""Idea persistence through the Data API, acting as the verified user.

Row-level security enforces ownership; every query also filters on the
caller's verified ID. Query paths and filters are built only from validated
UUIDs, integers and timestamps, never from client text. Provider error bodies
can contain submitted values, so they are neither returned nor logged: only
the provider status and SQLSTATE are logged.
"""

import logging
import uuid
from datetime import datetime
from typing import Any

import httpx2
from pydantic import ValidationError

from app.errors import ApiError
from app.ideas.models import Idea, IdeaCreate, IdeaSummary
from app.supabase_user import UserScopedSupabase

logger = logging.getLogger("app.ideas")

_IDEA_SELECT = (
    "id,title,description,notes,location,category,tags,created_at,updated_at,"
    "sources(id,kind,original_text,created_at)"
)
_SOURCE_ORDER = "created_at.asc,id.asc"
_RETURN_ROWS = {"Prefer": "return=representation"}
# SQLSTATEs for values the database refuses: a mismatch between API and SQL rules.
_INVALID_VALUE_CODES = frozenset({"22001", "22P02", "22P05", "23502", "23514"})


def _internal() -> ApiError:
    return ApiError(500, "internal_error", "Something went wrong.")


def _unexpected(operation: str, response: httpx2.Response) -> ApiError:
    code = _sqlstate(response)
    if response.status_code == 401:
        return ApiError(
            401,
            "invalid_token",
            "The access token is invalid or expired.",
            headers={"WWW-Authenticate": 'Bearer realm="api", error="invalid_token"'},
        )
    if response.status_code >= 500:
        logger.warning("%s: provider status %s", operation, response.status_code)
        return ApiError(503, "data_unavailable", "Your ideas are temporarily unavailable.")
    if code in _INVALID_VALUE_CODES:
        logger.warning("%s: database refused values (%s)", operation, code)
        return ApiError(422, "invalid_idea", "The idea contains values that cannot be saved.")
    logger.error("%s: unexpected provider status %s (%s)", operation, response.status_code, code)
    return _internal()


def _sqlstate(response: httpx2.Response) -> str | None:
    try:
        body = response.json()
    except ValueError:
        return None
    code = body.get("code") if isinstance(body, dict) else None
    return code if isinstance(code, str) else None


async def _call(
    db: UserScopedSupabase, operation: str, method: str, path: str, **kwargs: Any
) -> Any:
    """The decoded JSON body of a 2xx response, or an ApiError."""
    try:
        response = await db.rest(method, path, **kwargs)
    except httpx2.HTTPError as error:
        logger.warning("%s: data API request failed: %s", operation, type(error).__name__)
        raise ApiError(503, "data_unavailable", "Your ideas are temporarily unavailable.") from None
    if response.status_code != 200:
        raise _unexpected(operation, response)
    try:
        return response.json()
    except ValueError:
        logger.error("%s: provider returned an unexpected body", operation)
        raise _internal() from None


def _parse[T: IdeaSummary](operation: str, model: type[T], value: Any) -> T:
    try:
        return model.model_validate(value)
    except ValidationError:
        logger.error("%s: provider returned an unexpected row", operation)
        raise _internal() from None


def _rows(operation: str, body: Any) -> list[Any]:
    if not isinstance(body, list):
        logger.error("%s: provider returned an unexpected body", operation)
        raise _internal()
    return body


def _own(owner_id: uuid.UUID, idea_id: uuid.UUID) -> dict[str, str]:
    return {
        "id": f"eq.{idea_id}",
        "owner_id": f"eq.{owner_id}",
        "select": _IDEA_SELECT,
        "sources.order": _SOURCE_ORDER,
    }


async def create_idea(db: UserScopedSupabase, idea: IdeaCreate) -> Idea:
    body = await _call(
        db,
        "create",
        "POST",
        "rpc/create_idea",
        json={
            "p_title": idea.title,
            "p_description": idea.description,
            "p_notes": idea.notes,
            "p_location": idea.location,
            "p_category": idea.category,
            "p_tags": idea.tags,
            "p_original_text": idea.original_text,
        },
    )
    return _parse("create", Idea, body)


async def list_ideas(
    db: UserScopedSupabase,
    limit: int,
    before: tuple[datetime, uuid.UUID] | None,
    category: str | None = None,
) -> list[IdeaSummary]:
    args: dict[str, Any] = {"p_limit": limit, "p_category": category}
    if before is not None:
        args["p_before_created_at"] = before[0].isoformat()
        args["p_before_id"] = str(before[1])
    body = await _call(db, "list", "POST", "rpc/list_ideas", json=args)
    return [_parse("list", IdeaSummary, row) for row in _rows("list", body)]


async def get_idea(db: UserScopedSupabase, owner_id: uuid.UUID, idea_id: uuid.UUID) -> Idea | None:
    rows = _rows("get", await _call(db, "get", "GET", "ideas", params=_own(owner_id, idea_id)))
    return _parse("get", Idea, rows[0]) if rows else None


async def update_idea(
    db: UserScopedSupabase, owner_id: uuid.UUID, idea_id: uuid.UUID, changes: dict[str, Any]
) -> Idea | None:
    """Applies `changes`; None if the idea does not exist for this user."""
    body = await _call(
        db,
        "update",
        "PATCH",
        "ideas",
        params=_own(owner_id, idea_id),
        json=changes,
        headers=_RETURN_ROWS,
    )
    rows = _rows("update", body)
    return _parse("update", Idea, rows[0]) if rows else None


async def delete_idea(db: UserScopedSupabase, owner_id: uuid.UUID, idea_id: uuid.UUID) -> bool:
    """Deletes the idea and its sources; False if it does not exist for this user."""
    params = {"id": f"eq.{idea_id}", "owner_id": f"eq.{owner_id}", "select": "id"}
    body = await _call(db, "delete", "DELETE", "ideas", params=params, headers=_RETURN_ROWS)
    return bool(_rows("delete", body))
