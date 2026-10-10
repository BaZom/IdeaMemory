"""Verify the installed wheel imports and serves /health without the source tree.

Run with the interpreter of a fresh virtual environment that contains only the
pinned runtime dependencies and the built wheel, from a working directory
outside the repository.
"""

import asyncio
import json
import sys
import sysconfig
from pathlib import Path

from starlette.types import Message, Scope

import app
import app.main


def assert_installed_from_site_packages() -> None:
    site_packages = Path(sysconfig.get_paths()["purelib"]).resolve()
    package_dir = Path(app.__file__).resolve().parent
    if not package_dir.is_relative_to(site_packages):
        sys.exit(f"app imported from {package_dir}, expected under {site_packages}")


async def get_health() -> tuple[int, bytes]:
    sent: list[Message] = []
    request_delivered = False

    async def receive() -> Message:
        nonlocal request_delivered
        if request_delivered:
            await asyncio.Event().wait()
        request_delivered = True
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message: Message) -> None:
        sent.append(message)

    scope: Scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": "/health",
        "raw_path": b"/health",
        "query_string": b"",
        "root_path": "",
        "headers": [(b"host", b"testserver")],
        "client": ("127.0.0.1", 1),
        "server": ("testserver", 80),
    }
    await app.main.app(scope, receive, send)

    start = next(m for m in sent if m["type"] == "http.response.start")
    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body")
    return start["status"], body


def main() -> None:
    assert_installed_from_site_packages()
    status, body = asyncio.run(get_health())
    if status != 200 or json.loads(body) != {"status": "ok"}:
        sys.exit(f"unexpected /health response: {status} {body!r}")
    print(f"installed wheel OK: {Path(app.__file__).resolve().parent}")


if __name__ == "__main__":
    main()
