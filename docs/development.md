# Development workflow

## Present state

Task 001 and Task 002 are implemented locally. In the Flutter Web app users sign up and sign in with a **username and password** through a local Supabase stack; no email address is involved. The app shows the identity verified by the FastAPI `GET /api/v1/me` endpoint, and signs out; the public `GET /health` connection check remains as a diagnostic. Integration tests prove two-user isolation for database rows and private Storage objects using temporary fixtures. There is no idea schema, AI integration, hosted project or deployment (Tasks 003+).

## Current layout

```text
apps/mobile/                 Flutter Web app (package `mobile`; web platform only)
  lib/main.dart              reads public config, initialises Supabase, starts the app
  lib/config.dart            public build-time configuration (refuses secret keys)
  lib/auth/                  SDK gateway, session controller, auth gate, sign-in page, username mapping
  lib/account/               /api/v1/me client and signed-in page
  lib/connection_check/      /health client and connection-check diagnostic page
  test/                      config, clients, sign-in/session widget tests, fakes
  config/development.json    public build config (API URL, Supabase URL, publishable key)
  web/                       index.html, manifest.json, icons
services/api/
  pyproject.toml             package metadata, ranges, tool configuration
  requirements.txt           hashed runtime pins (incl. transitive)
  requirements-dev.txt       hashed runtime + dev pins (incl. pip/setuptools)
  src/app/main.py            ASGI app: /health, /api/v1/me, CORS, request IDs
  src/app/auth.py            bearer-token verification against Supabase Auth
  src/app/supabase_user.py   Data API/Storage access as the verified user
  src/app/settings.py        environment parsing; errors.py: error envelope
  tests/                     unit tests (fake provider); tests/integration/: real stack
  scripts/                   wheel check; optional local test-account provisioning
supabase/
  config.toml                local stack configuration (password sign-up, no confirmation)
scripts/install-supabase-cli.sh  pinned, checksum-verified project-local CLI install
.github/workflows/ci.yml     CI: same Make targets, pinned actions/toolchains
Makefile                     canonical setup/check/run entry points
.env.example                 local server overrides, public local values only
```

### Proposed eventual layout (later tasks; not created)

```text
apps/mobile/
  lib/features/              capture, collection, detail, chat
  lib/shared/                theme, widgets, REST client
  integration_test/          end-to-end flows
services/api/src/app/        ideas, sources, extraction, ai, recommendations
supabase/
  migrations/                ordered SQL schema, policies, functions
  tests/                     database/authorization cases
```

Create modules when their task needs them; no empty placeholders exist. Domain names stay independent of the working product name. Task 002 has no migrations: its isolation table and bucket are created and dropped by the integration tests.

## Toolchain (verified 2026-10-11)

| Tool | Version | Pinned where |
| --- | --- | --- |
| Flutter / Dart | 3.47.6 stable (framework 5fc346839b) / Dart 3.13.5 | `apps/mobile/pubspec.yaml` `environment.flutter`; Make targets fail on any other installed version (pub alone enforces only the lower bound); CI reads it |
| Python | 3.13.5 (any 3.13.x accepted locally; CI uses 3.13.5) | `pyproject.toml` `requires-python`, CI |
| pip | 26.2.1 (installed into the venv from the hashed lock) | `requirements-dev.txt` |
| Supabase CLI | 2.120.0 (MIT), installed into ignored `.tools/supabase-cli/` after SHA-256 verification; nothing global | `scripts/install-supabase-cli.sh` |
| Docker | Docker Desktop / engine (verified with 29.4.3) | — |
| GNU Make | 3.81 or later | — |
| Chrome | any current version, for `make run-web` | — |

Runtime: FastAPI 0.143.0, Uvicorn 0.54.0, httpx2 2.13.1 (Supabase Auth/Data API/Storage calls; already the test-client transport, so no Supabase Python SDK and its shared client session), Pydantic 2.14.0, Starlette 1.7.0. Dev: pytest 9.1.1, Ruff 0.17.0, mypy 2.4.0, build 1.6.1, hatchling 1.32.4, pip-tools 7.6.2. Flutter: `supabase_flutter` 2.18.2 (gotrue 2.27.3; MIT), `http` 1.6.0, `flutter_lints` 6.0.0. The CLI's telemetry is disabled by the Makefile (`SUPABASE_TELEMETRY_DISABLED`, `DO_NOT_TRACK`).

## Setup

From the repository root, on a machine with Flutter 3.47.6, Python 3.13 and a running Docker engine:

```sh
make setup            # API venv, Flutter packages, pinned Supabase CLI
make supabase-start   # local stack; first run pulls images
```

- `setup-api`: `python3.13 -m venv services/api/.venv`, then `services/api/.venv/bin/python -m pip install --require-hashes -r services/api/requirements-dev.txt` (the frozen install CI also uses). Pass `PYTHON=<interpreter>` if `python3.13` has another name.
- `setup-mobile`: `flutter pub get --enforce-lockfile` (fails rather than changing `pubspec.lock`).
- `setup-supabase`: downloads CLI 2.120.0 for this OS/architecture, verifies its checksum and installs it under `.tools/`. Re-running is a no-op.

The API source is not installed into the dev venv; tests use `pythonpath` and Uvicorn uses `--app-dir src`. Packaging is verified separately by the wheel check. To change Python dependencies, edit `pyproject.toml`, run `make lock-api`, then `make setup-api`. For a clean environment, `make clean && make setup`.

`make supabase-stop` stops the stack and keeps its data in Docker volumes; `make supabase-status` shows URLs and keys. `make list-users` lists local accounts by username. Normal users create accounts through **Sign up** in the app. `make provision-user USERNAME=<name> PASSWORD=<password>` is only an optional utility for test accounts.

## Running locally

```sh
make supabase-start   # if not already running
make run-api          # terminal 1: http://127.0.0.1:8000, verifies users against local Supabase
make run-web          # terminal 2: Chrome dev server at http://localhost:3000
```

1. Open http://localhost:3000. While the SDK restores any stored session it shows “Restoring your session…”, then the sign-in page.
2. New users choose **Sign up** and pick a username (3–30 letters, numbers, dots, dashes or underscores; case-insensitive) and a password (at least 8 characters); returning users stay on **Sign in**.
3. Press **Create account** / **Sign in**. The account page shows the username and the user ID verified by the API. Reload: the session is restored.
4. **Sign out** returns to sign-in immediately. The network icon opens the public connection check.

Sign-in never creates accounts. A wrong password and an unknown username get the same message (“Username or password is incorrect.”). A taken username is refused (“That username is taken…”) and leaves that account's password unchanged. There is no password recovery yet.

Release build served as static files:

```sh
make build-web   # apps/mobile/build/web
make serve-web   # python -m http.server on http://localhost:3000
```

## Configuration

| Scope | Name | Default / example | Meaning |
| --- | --- | --- | --- |
| Public Flutter build | `API_BASE_URL` | `http://localhost:8000` | API origin (optionally with path prefix). |
| Public Flutter build | `SUPABASE_URL` | `http://127.0.0.1:54321` | Supabase endpoint the browser uses for sign-in. |
| Public Flutter build | `SUPABASE_PUBLISHABLE_KEY` | local `sb_publishable_ACJW…` | Public key. The app refuses `sb_secret_…` and non-anon JWT keys at startup. |
| Server | `ALLOWED_ORIGINS` | `http://localhost:3000` | Exact CORS origins (`GET`, `Authorization` header, no credentials). Wildcards fail at startup. |
| Server | `SUPABASE_URL` | `http://127.0.0.1:54321` | Auth/Data/Storage endpoint the API calls. `http` is allowed only for loopback hosts. |
| Server | `SUPABASE_PUBLISHABLE_KEY` | local publishable key | The only Supabase key the API holds. |
| Server | `SUPABASE_JWT_ISSUER` | `http://127.0.0.1:54321/auth/v1` | Expected `iss` claim; fixed in `supabase/config.toml`. |
| Make (local) | `API_HOST`, `API_PORT`, `WEB_HOST`, `WEB_PORT`, `WEB_CONFIG`, `WEB_SUPABASE_URL` | `127.0.0.1`, `8000`, `localhost`, `3000`, `config/development.json`, `$(SUPABASE_URL)` | Local run ports/hosts, Flutter config file, Supabase URL compiled into LAN builds. |

The three server Supabase settings are all-or-nothing: if none are set, `/api/v1/me` returns `503 auth_not_configured` and `/health` still works; a partial or invalid set fails at startup. `make run-api` passes the local values (override via command line or `.env`). Flutter values come from `apps/mobile/config/development.json`, a personal ignored `config/<name>.local.json` via `WEB_CONFIG=`, or `API_BASE_URL=` (which switches to explicit `--dart-define`s, see the LAN section). Everything compiled into Flutter is public.

Privileged values (`SECRET_KEY`, `SERVICE_ROLE_KEY`, `JWT_SECRET` from `supabase status`) are used only by the optional `make provision-user`/`make list-users` utilities and integration-test fixtures, which read them from the running local stack. They are never in configuration files, the API's settings, the Flutter build or logs. Proposed for later tasks: `OPENAI_API_KEY`, `OPENAI_MODEL` (server only).

## Authentication behavior

- **Usernames (owner decision, 2026-10-11):** Supabase Auth identifies accounts by email, so the app maps each username to the placeholder address `<username>@users.invalid` (`lib/auth/username.dart`). `.invalid` is a reserved domain that can never receive mail; users never see it. The SDK calls are `signUp` and `signInWithPassword`. Provider settings: `[auth] enable_signup = true`, `[auth.email] enable_confirmations = false` (sign-up returns a session immediately), `minimum_password_length = 8`, anonymous sign-in off. Accepted for the MVP: no account recovery or verification; account security beyond the password is out of scope until real users (Task 008). Hosted Supabase may validate addresses more strictly; recheck the placeholder domain when hosting. Per-account data isolation (API token verification, RLS, private Storage) is unchanged.
- **Passwords:** stored and checked only by Supabase Auth (bcrypt); the app and API never see or log them. Rate limits are the provider's (`[auth.rate_limit]`).
- **Sessions:** `supabase_flutter` stores and refreshes the session (browser local storage; readable by scripts on the page, an accepted tradeoff: no third-party scripts or untrusted HTML). Tokens are never read from URLs (`detectSessionInUri: false`) and never logged.
- **API verification:** every `/api/v1/me` call is verified online with `GET /auth/v1/user`. The API first refuses malformed tokens, shared-secret (HS*) algorithms, wrong issuer/audience/role, anonymous users, past expiry and non-UUID subjects, then requires the provider-returned user to match the token subject. Provider timeout, outage or unexpected response → `503 auth_unavailable`; rejection → `401` with `WWW-Authenticate: Bearer`. Responses use `Cache-Control: no-store`. On a 401 the app refreshes once through the SDK and retries once.
- **Algorithm restriction:** the local stack still accepts HS256 tokens signed with its publicly known legacy secret; the API refuses them. A hosted project must therefore use asymmetric JWT signing keys (Task 008 hosting decision).
- **Sign-out:** local scope (this device). The UI clears immediately; the SDK then ends the session at the provider, and a failed server call is reported. After sign-out the API refuses the old access token at once (`session_not_found`). Supabase Data API and Storage verify tokens locally, so a copied access token keeps working there until it expires (`jwt_expiry` = 1 hour); there is no custom revocation list.
- **Account switch:** each signed-in identity gets a fresh page state and a session generation; responses or refreshes from an earlier session are discarded.

## Physical iPhone check (LAN, non-sensitive)

An iPhone cannot reach the Mac's `localhost`. On a trusted Wi-Fi network only:

```sh
IP=$(ipconfig getifaddr en0)   # Mac's LAN address (interface may differ)
make supabase-start
make run-api API_HOST=0.0.0.0 ALLOWED_ORIGINS=http://$IP:3000                              # terminal 1
make build-web API_BASE_URL=http://$IP:8000 WEB_SUPABASE_URL=http://$IP:54321 && make serve-web WEB_HOST=0.0.0.0   # terminal 2
```

Open `http://<IP>:3000` in Safari. The API still talks to Supabase at `127.0.0.1`, and tokens keep the issuer `http://127.0.0.1:54321/auth/v1` even when the phone reaches Supabase via the LAN address, so issuer checks stay on. Follow the [Task 002 manual test](manual-tests/002-auth.md) (and [Task 001](manual-tests/001-bootstrap.md) for the connection check). Plain HTTP; HTTPS, installation and updates are Task 008 checks. Do not create public tunnels or hosted environments without authorization.

**Local stack exposure:** the Supabase CLI publishes its ports on all interfaces (`0.0.0.0`), and there is no CLI setting to change that. While the stack runs, devices on your network can reach the API gateway (54321), Postgres (54322, default credentials `postgres`/`postgres`) and the Mailpit inbox (54324). Studio, pg-meta, realtime, analytics and edge functions are disabled. Run the stack only on trusted networks and stop it (`make supabase-stop`) when done. Alternative: set Docker Engine's default bind address to `127.0.0.1` (Docker Desktop → Settings → Docker Engine, `"ip": "127.0.0.1"`); this protects the database and inbox but also prevents the LAN phone check.

## Canonical validation

```sh
make check   # = check-mobile + check-api + check-integration; stops with nonzero exit on the first failure
```

| Target | Commands (run in the component directory) |
| --- | --- |
| `check-mobile` | `flutter pub get --enforce-lockfile`; `dart format --output=none --set-exit-if-changed lib test`; `flutter analyze --fatal-infos`; `flutter test`; `flutter build web --release` into `build/check-web` (never overwrites `build/web`) |
| `check-api` | `ruff check .`; `ruff format --check .`; `mypy` (strict; `src`, `tests`, `scripts`); `pytest` (unit tests; warnings are errors; integration excluded); then `check-api-wheel` |
| `check-api-wheel` | builds the wheel, installs it with only hashed runtime pins into a fresh venv, `pip check`, and runs `scripts/check_installed_wheel.py` in isolated mode from a temporary directory |
| `check-integration` | `supabase start` (idempotent), then `pytest -m integration` with the running stack's settings: username (placeholder-address) sign-up with an immediate session (incl. first data write as the new user), returning-user sign-in, identical errors for wrong password and unknown account, duplicate sign-up refusal without changing the owner's password, weak-password refusal, real-token `/api/v1/me` incl. forged/expired/revoked/deleted tokens and outages, concurrent users, and two-user RLS and private-Storage isolation through both direct provider calls and the API's user-scoped boundary (test-only routes) |

Integration fixtures create synthetic users, a temporary owner-scoped table and a private bucket with unique names, and remove them afterwards; fixtures are never added to migrations or the shipped app (a unit test asserts the shipped routes/OpenAPI paths). A missing CLI, stopped Docker, stopped stack or missing environment fails with an explicit error; nothing is skipped. `make check` does not modify sources.

CI (`.github/workflows/ci.yml`) runs `mobile`, `api` and `integration` jobs on `ubuntu-24.04` with read-only permissions, commit-pinned actions, bounded timeouts and no repository secrets (the integration job uses the disposable stack's own local keys). Physical Safari and manual checks remain separately recorded; local command success does not imply them.

## Migrations and database development

Add numbered SQL migrations with each vertical slice, not the entire eventual domain in advance. Migrations include constraints, policies, grants and RPC definitions; never rely on undocumented dashboard edits. Test fresh application and upgrade from previous schema with representative data. Never edit applied migrations; add a forward corrective migration. Destructive operations need explicit approval and a tested backup/restore plan. Local reset is only for disposable local databases, never a hosted project. Use synthetic fixtures and two-user authorization tests.

## Branches, PRs and responsibilities

Propose `main` as the eventual protected default branch; current unborn `master` has not been renamed. Use short branches (`codex/<topic>` for Codex work; `feature/<task>-<topic>` for Claude work). One coherent task/slice per PR; if a task becomes large, agree smaller acceptance-preserving slices before implementation.

Codex inspects and plans → human approves necessary scope/decisions → Claude implements/tests → Codex reviews actual changes → Claude fixes accepted findings → CI validates final commit → human merges/releases. PR descriptions state behavior, scope, plan reference, checks/results, migration impact, and remaining limitations. Approval and checks apply to the reviewed revision, not later unseen changes. Follow [engineering standards](engineering-standards.md) for proportional planning and finding format. No automatic approval based on Claude's summary.
