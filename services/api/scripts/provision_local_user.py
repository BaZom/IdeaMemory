"""Optional operator tool: create (or list) confirmed synthetic users on the
LOCAL Supabase stack, e.g. for test data. Normal users sign up in the app.
The secret key is read from the environment (`make provision-user` supplies
it from `supabase status`) and is never printed. Non-local URLs are refused,
so this cannot touch a hosted project.

Accounts are identified by username; like the app, a username maps to the
placeholder address `<username>@users.invalid`.

Usage: PROVISION_PASSWORD=<password> provision_local_user.py <username>
       provision_local_user.py --list
"""

import os
import re
import sys
from urllib.parse import urlsplit

import httpx2

_LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}
_USERNAME = re.compile(r"^[a-z0-9][a-z0-9._-]{2,29}$")
_DOMAIN = "@users.invalid"


def main(argv: list[str]) -> int:
    url = os.environ.get("SB_API_URL", "").rstrip("/")
    secret = os.environ.get("SB_SECRET_KEY", "")
    if not url or not secret:
        print("error: run via `make provision-user EMAIL=...`", file=sys.stderr)
        return 2
    if urlsplit(url).hostname not in _LOCAL_HOSTS:
        print(f"error: refusing non-local Supabase URL {url}", file=sys.stderr)
        return 2
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2

    headers = {"apikey": secret, "Authorization": f"Bearer {secret}"}
    with httpx2.Client(timeout=10, trust_env=False) as client:
        if argv[0] == "--list":
            response = client.get(
                f"{url}/auth/v1/admin/users", headers=headers, params={"per_page": "1000"}
            )
            response.raise_for_status()
            for user in response.json()["users"]:
                email = user.get("email") or ""
                print(f"{user['id']}  {email.removesuffix(_DOMAIN)}")
            return 0

        username = argv[0].strip().lower()
        if not _USERNAME.fullmatch(username):
            print(f"error: {username!r} is not a valid username", file=sys.stderr)
            return 2
        email = username + _DOMAIN
        password = os.environ.get("PROVISION_PASSWORD", "")
        if len(password) < 8:
            print("error: give a password of at least 8 characters (PASSWORD=...)", file=sys.stderr)
            return 2
        response = client.post(
            f"{url}/auth/v1/admin/users",
            headers=headers,
            json={"email": email, "password": password, "email_confirm": True},
        )
        if response.status_code == 422 and response.json().get("error_code") == "email_exists":
            print(f"{username} already exists")
            return 0
        response.raise_for_status()
        print(f"created {username} ({response.json()['id']}); sign in with its password")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
