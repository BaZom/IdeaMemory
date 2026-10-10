"""ASGI application entry point."""

from collections.abc import Sequence
from typing import Literal

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.settings import allowed_origins_from_env


class HealthResponse(BaseModel):
    status: Literal["ok"]


def create_app(allowed_origins: Sequence[str]) -> FastAPI:
    application = FastAPI(title="API")
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(allowed_origins),
        allow_methods=["GET"],
        allow_credentials=False,
    )

    @application.get("/health")
    def health() -> HealthResponse:
        """Process liveness only; performs no external calls or dependency checks."""
        return HealthResponse(status="ok")

    return application


app = create_app(allowed_origins_from_env())
