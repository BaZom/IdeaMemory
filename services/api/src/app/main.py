"""ASGI application entry point."""

import logging
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable, Sequence
from contextlib import asynccontextmanager
from typing import Literal

import httpx2
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.auth import CurrentUser, TokenVerifier
from app.errors import install_error_handlers
from app.settings import (
    SupabaseSettings,
    allowed_origins_from_env,
    supabase_settings_from_env,
)

logger = logging.getLogger("app.request")


class HealthResponse(BaseModel):
    status: Literal["ok"]


class MeResponse(BaseModel):
    user_id: uuid.UUID


def create_app(
    allowed_origins: Sequence[str],
    supabase: SupabaseSettings | None = None,
    *,
    http_transport: httpx2.AsyncBaseTransport | None = None,
) -> FastAPI:
    """Build the API. `http_transport` replaces the network in tests."""

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        if supabase is None:
            yield
            return
        # One shared connection pool; credentials are set per request only.
        async with httpx2.AsyncClient(transport=http_transport, trust_env=False) as client:
            application.state.http_client = client
            application.state.supabase_settings = supabase
            application.state.token_verifier = TokenVerifier(supabase, client)
            yield

    application = FastAPI(title="API", lifespan=lifespan)
    application.state.token_verifier = None
    install_error_handlers(application)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(allowed_origins),
        allow_methods=["GET"],
        allow_headers=["Authorization"],
        expose_headers=["X-Request-ID"],
        allow_credentials=False,
    )

    @application.middleware("http")
    async def request_id(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        # Logs carry method, path and status only: never headers, tokens or bodies.
        rid = uuid.uuid4().hex
        started = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Request-ID"] = rid
        logger.info(
            "%s %s %s %.1fms rid=%s",
            request.method,
            request.url.path,
            response.status_code,
            (time.perf_counter() - started) * 1000,
            rid,
        )
        return response

    @application.get("/health")
    def health() -> HealthResponse:
        """Process liveness only; performs no external calls or dependency checks."""
        return HealthResponse(status="ok")

    @application.get("/api/v1/me")
    def me(user: CurrentUser, response: Response) -> MeResponse:
        """The caller's identity as verified by the auth provider."""
        response.headers["Cache-Control"] = "no-store"
        return MeResponse(user_id=user.user_id)

    return application


app = create_app(allowed_origins_from_env(), supabase_settings_from_env())
