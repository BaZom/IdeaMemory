# Development workflow

## Present state

Task 001 (bootstrap) is implemented: a Flutter Web connection-check shell, a FastAPI service exposing `GET /health`, pinned toolchains/dependencies, a root `Makefile` and GitHub Actions CI. Authentication, Supabase, database schema, OpenAI and deployment do not exist yet (Tasks 002+).

## Current layout

```text
apps/mobile/                 Flutter Web app (package `mobile`; web platform only)
  lib/main.dart              reads API_BASE_URL, starts the shell
  lib/config.dart            public build-time configuration parsing
  lib/connection_check/      health client (package:http) and connection-check page
  test/                      config, health client and widget tests
  config/development.json    public build config (API_BASE_URL only; no secrets)
  web/                       index.html, manifest.json, icons
  pubspec.yaml / pubspec.lock  exact Flutter pin and committed lockfile
services/api/
  pyproject.toml             package metadata, ranges, tool configuration
  requirements.txt           hashed runtime pins (incl. transitive)
  requirements-dev.txt       hashed runtime + dev pins (incl. pip/setuptools)
  src/app/                   main.py (ASGI app, /health, CORS), settings.py
  tests/                     health contract, CORS and settings tests
  scripts/check_installed_wheel.py  clean-wheel install verification
.github/workflows/ci.yml     CI: same Make targets, pinned actions/toolchains
Makefile                     canonical setup/check/run entry points
.env.example                 local server overrides, dummy values only
```

### Proposed eventual layout (later tasks; not created)

```text
apps/mobile/
  lib/features/              auth, capture, collection, detail, chat
  lib/shared/                theme, widgets, REST client
  integration_test/          end-to-end flows
services/api/src/app/        auth, ideas, sources, extraction, ai, recommendations
supabase/
  config.toml                local stack configuration
  migrations/                ordered SQL schema, policies, functions
  tests/                     database/authorization cases
scripts/                     only scripts needed by real workflows
```

Create modules when their task needs them; no empty placeholders exist. Domain names stay independent of the working product name. Task 002 adds `supabase start` / `supabase db reset` (local disposable database only; resets delete local data) and Docker as prerequisites.

## Toolchain (verified 2026-10-11)

| Tool | Version | Pinned where |
| --- | --- | --- |
| Flutter / Dart | 3.47.6 stable (framework 5fc346839b) / Dart 3.13.5 | `apps/mobile/pubspec.yaml` `environment.flutter` (pub rejects other versions; CI reads it) |
| Python | 3.13.5 (any 3.13.x accepted locally; CI uses 3.13.5) | `pyproject.toml` `requires-python`, CI |
| pip | 26.2.1 (installed into the venv from the hashed lock) | `requirements-dev.txt` |
| GNU Make | 3.81 or later | — |
| Chrome | any current version, for `make run-web` | — |

Runtime: FastAPI 0.143.0, Uvicorn 0.54.0 (Pydantic 2.14.0, Starlette 1.7.0). Dev: pytest 9.1.1, httpx2 2.13.1 (Starlette's TestClient transport), Ruff 0.17.0, mypy 2.4.0, build 1.6.1, hatchling 1.32.4, pip-tools 7.6.2. Flutter: `http` 1.6.0, `flutter_lints` 6.0.0. Docker and the Supabase CLI are not required yet.

## Setup

From the repository root, on a machine with Flutter 3.47.6 and Python 3.13 on `PATH`:

```sh
make setup
```

This runs:

- `setup-api`: `python3.13 -m venv services/api/.venv`, then `services/api/.venv/bin/python -m pip install --require-hashes -r services/api/requirements-dev.txt` (the frozen install CI also uses; every package, including transitive ones, must match a pinned hash). Pass `PYTHON=<interpreter>` if `python3.13` has another name; setup refuses non-3.13 interpreters.
- `setup-mobile`: `flutter pub get --enforce-lockfile` in `apps/mobile` (fails rather than changing `pubspec.lock`).

The API source is not installed into the dev venv; tests use `pythonpath = ["src"]` and Uvicorn uses `--app-dir src`. Packaging is verified separately by the wheel check. No provider credentials are needed.

To change Python dependencies, edit `services/api/pyproject.toml`, run `make lock-api` (regenerates both hashed files with pip-tools in a throwaway venv), then `make setup-api`. For a clean environment, `make clean && make setup`.

## Running locally

```sh
make run-api   # terminal 1: http://127.0.0.1:8000, reload, ALLOWED_ORIGINS=http://localhost:3000
make run-web   # terminal 2: Chrome dev server at http://localhost:3000
```

Open http://localhost:3000. The page checks `GET /health` once on load and shows “Checking connection…”, then “Connected” or “Connection failed” with a **Retry** button. Stop the API to see failure, restart it, and press Retry to recover. There is no automatic polling or retry.

Release build served as static files (closer to deployment; also used for the LAN check):

```sh
make build-web   # apps/mobile/build/web
make serve-web   # python -m http.server on http://localhost:3000
```

## Configuration

| Scope | Name | Default / example | Meaning |
| --- | --- | --- | --- |
| Public Flutter build | `API_BASE_URL` | `http://localhost:8000` in `apps/mobile/config/development.json` | API origin (optionally with path prefix). Required: a missing or invalid value shows a configuration error page. |
| Server | `ALLOWED_ORIGINS` | `http://localhost:3000` (Makefile default) | Comma-separated exact CORS origins. Unset means no cross-origin access; wildcards, paths and non-http(s) values fail at startup. |
| Make (local) | `API_HOST`, `API_PORT`, `WEB_HOST`, `WEB_PORT`, `WEB_CONFIG` | `127.0.0.1`, `8000`, `localhost`, `3000`, `config/development.json` | Local run ports/hosts and Flutter config file. |

Override per command (`make run-api ALLOWED_ORIGINS=http://localhost:3000,http://192.168.1.20:3000`, `make build-web API_BASE_URL=http://192.168.1.20:8000`), via a personal `apps/mobile/config/<name>.local.json` with `WEB_CONFIG=config/<name>.local.json` (ignored by Git), or by copying `.env.example` to `.env` (ignored; read by the Makefile). Everything compiled into Flutter is public: only `API_BASE_URL` is defined. CORS allows only `GET`, without credentials.

Proposed for later tasks (not implemented): `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (Flutter and server), `OPENAI_API_KEY`, `OPENAI_MODEL` (server, optional until AI tasks), `SUPABASE_SECRET_KEY` (operator only). Validate required settings by enabled capability; absent AI configuration must not prevent manual CRUD. Secrets belong in ignored local settings and host/CI secret stores. Never paste credentials or private screenshots into test fixtures or logs. The server starts today without any of these.

## Physical iPhone smoke check (LAN, non-sensitive)

An iPhone cannot reach the Mac's `localhost`. On a trusted Wi-Fi network only, with the phone and Mac on the same network:

```sh
IP=$(ipconfig getifaddr en0)   # Mac's LAN address (interface may differ)
make run-api API_HOST=0.0.0.0 ALLOWED_ORIGINS=http://$IP:3000     # terminal 1
make build-web API_BASE_URL=http://$IP:8000 && make serve-web WEB_HOST=0.0.0.0   # terminal 2
```

Open `http://<IP>:3000` in Safari (allow incoming connections if macOS asks). Then follow the [Task 001 manual test](manual-tests/001-bootstrap.md) (Part B), which implements the procedure in [Task 001](plans/001-mvp.md#physical-iphone-smoke-procedure): record device, iOS/Safari version, date and revision; confirm “Connected”; stop the API and reload to see “Connection failed”; restart it and press Retry to recover; check portrait and landscape. This exposes unauthenticated development servers to the LAN, so stop both afterwards. It is plain HTTP and does not verify HTTPS, home-screen installation or updates (Task 008). Do not create public tunnels or hosted environments without authorization.

## Canonical validation

```sh
make check   # = check-mobile + check-api; stops with nonzero exit on the first failure
```

| Target | Commands (run in the component directory) |
| --- | --- |
| `check-mobile` | `flutter pub get --enforce-lockfile`; `dart format --output=none --set-exit-if-changed lib test`; `flutter analyze --fatal-infos`; `flutter test`; `flutter build web --release --dart-define-from-file=config/development.json` |
| `check-api` | `ruff check .`; `ruff format --check .`; `mypy` (strict; `src`, `tests`, `scripts`); `pytest` (warnings are errors); then `check-api-wheel` |
| `check-api-wheel` | `python -m build --wheel --no-isolation`; fresh venv with `pip install --require-hashes -r requirements.txt`; `pip install --no-deps --no-index` the wheel; `pip check`; from a temporary directory, `python -I scripts/check_installed_wheel.py` (asserts `app` is imported from site-packages and `/health` returns the contract) |

Missing `flutter`/`dart`/Python or a missing API venv fails with an explicit error (exit 127/1); nothing is skipped. `make check` does not modify sources; it writes ignored build outputs (`apps/mobile/build`, `services/api/{dist,build}`). Database integration checks join in Task 002. CI (`.github/workflows/ci.yml`) runs `make setup-mobile check-mobile` and `make setup-api check-api` in parallel jobs on `ubuntu-24.04`, with read-only permissions, commit-pinned actions, bounded timeouts and no secrets. Physical Safari and manual AI evaluations remain separate recorded checks; local command success does not imply them.

## Migrations and database development

Add numbered SQL migrations with each vertical slice, not the entire eventual domain in advance. Migrations include constraints, policies, grants and RPC definitions; never rely on undocumented dashboard edits. Test fresh application and upgrade from previous schema with representative data. Never edit applied migrations; add a forward corrective migration. Destructive operations need explicit approval and a tested backup/restore plan. Local reset is only for disposable local databases, never a hosted project. Use synthetic fixtures and two-user authorization tests.

## Branches, PRs and responsibilities

Propose `main` as the eventual protected default branch; current unborn `master` has not been renamed. Use short branches (`codex/<topic>` for Codex work; `feature/<task>-<topic>` for Claude work). One coherent task/slice per PR; if a task becomes large, agree smaller acceptance-preserving slices before implementation.

Codex inspects and plans → human approves necessary scope/decisions → Claude implements/tests → Codex reviews actual changes → Claude fixes accepted findings → CI validates final commit → human merges/releases. PR descriptions state behavior, scope, plan reference, checks/results, migration impact, and remaining limitations. Approval and checks apply to the reviewed revision, not later unseen changes. Follow [engineering standards](engineering-standards.md) for proportional planning and finding format. No automatic approval based on Claude's summary.
