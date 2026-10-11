"""Supabase Data API and Storage access as one verified user.

Requests carry the user's own access token, so database row-level security and
storage policies apply. Credentials are attached per request; the shared HTTP
client never holds a user's authorization, so concurrent requests cannot leak
identity between users. No privileged key is available here.
"""

from collections.abc import Mapping
from typing import Annotated, Any

import httpx2
from fastapi import Depends, Request

from app.auth import CurrentUser, VerifiedUser
from app.settings import SupabaseSettings

DATA_TIMEOUT = httpx2.Timeout(10.0)


class UserScopedSupabase:
    def __init__(
        self, client: httpx2.AsyncClient, settings: SupabaseSettings, user: VerifiedUser
    ) -> None:
        self._client = client
        self._settings = settings
        self._user = user

    def _headers(self, extra: Mapping[str, str] | None) -> dict[str, str]:
        return {
            "apikey": self._settings.publishable_key,
            "Authorization": f"Bearer {self._user.access_token}",
            **(extra or {}),
        }

    async def rest(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, str] | None = None,
        json: Any = None,
        headers: Mapping[str, str] | None = None,
    ) -> httpx2.Response:
        """Call the Data API (PostgREST) at `/rest/v1/<path>`."""
        return await self._client.request(
            method,
            f"{self._settings.url}/rest/v1/{path.lstrip('/')}",
            params=params,
            json=json,
            headers=self._headers(headers),
            timeout=DATA_TIMEOUT,
            follow_redirects=False,
        )

    async def storage(
        self,
        method: str,
        path: str,
        *,
        content: bytes | None = None,
        json: Any = None,
        headers: Mapping[str, str] | None = None,
    ) -> httpx2.Response:
        """Call the Storage API at `/storage/v1/<path>`."""
        return await self._client.request(
            method,
            f"{self._settings.url}/storage/v1/{path.lstrip('/')}",
            content=content,
            json=json,
            headers=self._headers(headers),
            timeout=DATA_TIMEOUT,
            follow_redirects=False,
        )


def user_supabase(request: Request, user: CurrentUser) -> UserScopedSupabase:
    """FastAPI dependency: Supabase access scoped to the verified caller."""
    state = request.app.state
    return UserScopedSupabase(state.http_client, state.supabase_settings, user)


UserSupabase = Annotated[UserScopedSupabase, Depends(user_supabase)]
