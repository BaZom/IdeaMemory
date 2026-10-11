"""Idea request/response schemas and text rules.

The API is the authority for idea values; the database constraints check the
same limits. Lengths count Unicode code points; whitespace is exactly
`WHITESPACE` (the set the database's trim check uses). Validation errors carry
only a field path and an error code, never the submitted value.
"""

import uuid
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator
from pydantic_core import PydanticCustomError

WHITESPACE = (
    "\t\n\x0b\x0c\r \x85\xa0\u1680"
    "\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a"
    "\u2028\u2029\u202f\u205f\u3000\ufeff"
)
TITLE_MAX = 200
LONG_TEXT_MAX = 10_000
LOCATION_MAX = 300
ORIGINAL_TEXT_MAX = 20_000
TAG_MAX = 50
TAGS_MAX = 20
# Raw entries accepted before de-duplication; anything longer is oversized input.
TAG_ENTRIES_MAX = 100

Category = Literal[
    "food", "activity", "travel", "film-series", "recipe", "product", "book", "place", "other"
]


def _error(code: str, message: str) -> PydanticCustomError:
    return PydanticCustomError(code, message)


def _check_characters(value: str) -> None:
    # NUL cannot be stored; lone surrogates cannot be encoded as UTF-8.
    if "\x00" in value or any("\ud800" <= char <= "\udfff" for char in value):
        raise _error("unsupported_character", "Contains an unsupported character.")


def trim(value: str) -> str:
    return value.strip(WHITESPACE)


def normalize_title(value: str) -> str:
    _check_characters(value)
    title = trim(value)
    if not title:
        raise _error("blank", "Enter a title.")
    if len(title) > TITLE_MAX:
        raise _error("too_long", "Too long.")
    return title


def _optional_text(max_length: int) -> Any:
    def normalize(value: str | None) -> str | None:
        if value is None:
            return None
        _check_characters(value)
        text = trim(value)
        if len(text) > max_length:
            raise _error("too_long", "Too long.")
        return text or None

    return AfterValidator(normalize)


def normalize_original_text(value: str | None) -> str | None:
    """Kept exactly as supplied; only checked."""
    if value is None:
        return None
    _check_characters(value)
    if not trim(value):
        raise _error("blank", "Original text must contain visible characters.")
    if len(value) > ORIGINAL_TEXT_MAX:
        raise _error("too_long", "Too long.")
    return value


def normalize_tags(values: list[str]) -> list[str]:
    """Trimmed, de-duplicated case-insensitively keeping the first spelling."""
    if len(values) > TAG_ENTRIES_MAX:
        raise _error("too_many", "Too many tags.")
    tags: list[str] = []
    seen: set[str] = set()
    for value in values:
        _check_characters(value)
        tag = trim(value)
        if not tag:
            raise _error("blank", "Tags cannot be blank.")
        if len(tag) > TAG_MAX:
            raise _error("too_long", "Tag too long.")
        key = tag.lower()
        if key not in seen:
            seen.add(key)
            tags.append(tag)
    if len(tags) > TAGS_MAX:
        raise _error("too_many", "Too many tags.")
    return tags


Title = Annotated[str, AfterValidator(normalize_title)]
LongText = Annotated[str | None, _optional_text(LONG_TEXT_MAX)]
Location = Annotated[str | None, _optional_text(LOCATION_MAX)]
OriginalText = Annotated[str | None, AfterValidator(normalize_original_text)]
Tags = Annotated[list[str], AfterValidator(normalize_tags)]

_REQUEST_CONFIG = ConfigDict(extra="forbid", strict=True)


class IdeaCreate(BaseModel):
    model_config = _REQUEST_CONFIG

    title: Title
    description: LongText = None
    notes: LongText = None
    location: Location = None
    category: Category | None = None
    tags: Tags = Field(default_factory=list)
    original_text: OriginalText = None


EDITABLE_FIELDS = ("title", "description", "notes", "location", "category", "tags")
_NOT_NULLABLE = ("title", "tags")


class IdeaUpdate(BaseModel):
    """Omitted fields stay unchanged; null clears an optional field."""

    model_config = _REQUEST_CONFIG

    title: Title | None = None
    description: LongText = None
    notes: LongText = None
    location: Location = None
    category: Category | None = None
    tags: Tags | None = None

    @model_validator(mode="after")
    def _check_changes(self) -> "IdeaUpdate":
        if not self.model_fields_set.intersection(EDITABLE_FIELDS):
            raise _error("no_changes", "Provide at least one field to change.")
        for name in _NOT_NULLABLE:
            if name in self.model_fields_set and getattr(self, name) is None:
                raise _error("not_nullable", "This field cannot be cleared.")
        return self

    def changes(self) -> dict[str, Any]:
        return {
            name: getattr(self, name) for name in EDITABLE_FIELDS if name in self.model_fields_set
        }


class Source(BaseModel):
    id: uuid.UUID
    kind: Literal["text"]
    original_text: str
    created_at: datetime


class IdeaSummary(BaseModel):
    id: uuid.UUID
    title: str
    description: str | None
    notes: str | None
    location: str | None
    category: Category | None
    tags: list[str]
    created_at: datetime
    updated_at: datetime


class Idea(IdeaSummary):
    sources: list[Source]


class IdeaPage(BaseModel):
    items: list[IdeaSummary]
    next_cursor: str | None
