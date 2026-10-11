"""Consistent JSON error envelope: {"error": {"code": ..., "message": ...}}.

Validation errors add `fields`: a path and an error code per problem. Submitted
values are never echoed back, because they can be private text.
"""

import logging
from collections.abc import Mapping
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

logger = logging.getLogger("app.errors")

MAX_REQUEST_BODY_BYTES = 256 * 1024


class ApiError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.headers = dict(headers or {})


def error_response(error: ApiError, extra: Mapping[str, Any] | None = None) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={"error": {"code": error.code, "message": error.message, **(extra or {})}},
        headers={"Cache-Control": "no-store", **error.headers},
    )


def _field_errors(exc: RequestValidationError) -> list[dict[str, str]]:
    fields = []
    for problem in exc.errors():
        # loc is e.g. ("body", "tags", 3) or ("header", "idempotency-key").
        path = ".".join(str(part) for part in problem.get("loc", ())[1:])
        fields.append({"field": path or "body", "code": str(problem.get("type", "invalid"))})
    return fields


def install_error_handlers(application: FastAPI) -> None:
    async def handle_api_error(_request: Request, exc: Exception) -> JSONResponse:
        if not isinstance(exc, ApiError):  # pragma: no cover - registered for ApiError only
            raise exc
        return error_response(exc)

    async def handle_validation_error(_request: Request, exc: Exception) -> JSONResponse:
        if not isinstance(exc, RequestValidationError):  # pragma: no cover
            raise exc
        return error_response(
            ApiError(422, "invalid_request", "Some values are missing or invalid."),
            {"fields": _field_errors(exc)},
        )

    async def handle_unexpected(_request: Request, exc: Exception) -> JSONResponse:
        # The type only: exception messages may contain request data.
        logger.error("unhandled %s", type(exc).__name__)
        return error_response(ApiError(500, "internal_error", "Something went wrong."))

    application.add_exception_handler(ApiError, handle_api_error)
    application.add_exception_handler(RequestValidationError, handle_validation_error)
    application.add_exception_handler(Exception, handle_unexpected)


class BodySizeLimit:
    """Rejects request bodies over `max_bytes` with 413 before anything parses them."""

    def __init__(self, app: ASGIApp, max_bytes: int = MAX_REQUEST_BODY_BYTES) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        too_large = error_response(ApiError(413, "request_too_large", "The request is too large."))
        declared = dict(scope["headers"]).get(b"content-length")
        if declared is not None and (not declared.isdigit() or int(declared) > self.max_bytes):
            await too_large(scope, receive, send)
            return

        # Read the whole (bounded) body, then replay it to the application.
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] != "http.request":
                await self.app(scope, _replay([message], receive), send)
                return
            body += message.get("body", b"")
            if len(body) > self.max_bytes:
                await too_large(scope, receive, send)
                return
            if not message.get("more_body", False):
                break
        replayed: Message = {"type": "http.request", "body": bytes(body), "more_body": False}
        await self.app(scope, _replay([replayed], receive), send)


def _replay(messages: list[Message], receive: Receive) -> Receive:
    pending = list(messages)

    async def replay() -> Message:
        return pending.pop(0) if pending else await receive()

    return replay
