"""Consistent JSON error envelope: {"error": {"code": ..., "message": ...}}."""

from collections.abc import Mapping

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


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


def error_response(error: ApiError) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={"error": {"code": error.code, "message": error.message}},
        headers={"Cache-Control": "no-store", **error.headers},
    )


def install_error_handlers(application: FastAPI) -> None:
    async def handle_api_error(_request: Request, exc: Exception) -> JSONResponse:
        if not isinstance(exc, ApiError):  # pragma: no cover - registered for ApiError only
            raise exc
        return error_response(exc)

    application.add_exception_handler(ApiError, handle_api_error)
