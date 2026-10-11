# Idea Memory

Working title: a private, conversational memory for things you want to experience.

**Status: Task 002 (self-service sign-up, sign-in and private access) is implemented locally, pending Codex review, remote CI and manual device verification.** Task 001 is reviewed and its CI passed. Task 002 was approved on 2026-10-11; Tasks 003–008 are not approved. Supabase runs only as a local Docker stack; no hosted project, deployment or OpenAI configuration exists.

The repository contains a Flutter Web app (`apps/mobile/`) where users sign up and sign in with a username and password, a FastAPI service (`services/api/`) with a public `GET /health` and a protected `GET /api/v1/me`, local Supabase configuration (`supabase/`), a root `Makefile` and a GitHub Actions workflow. See [development](docs/development.md) for setup, configuration, authentication behavior and validation.

Prerequisites: Flutter 3.47.6, Python 3.13, a running Docker engine.

```sh
make setup                                   # Python venv, Flutter packages, pinned Supabase CLI
make supabase-start                          # local Supabase stack (Docker)
make check                                   # every canonical check incl. real auth/isolation tests
make run-api                                 # terminal 1: API on http://127.0.0.1:8000
make run-web                                 # terminal 2: app on http://localhost:3000
```

Open the app, choose **Sign up** and pick a username and a password (at least 8 characters); you are signed in immediately, and each account sees only its own data. Return later through **Sign in**. No email address is involved (owner decision for the MVP; account recovery and verification come later). `make provision-user USERNAME=... PASSWORD=...` exists only for optional test accounts. Stop the stack with `make supabase-stop` when you are done: its ports, including the database, are reachable from your network while it runs.

### Run on an iPhone (same Wi-Fi)

An iPhone cannot reach the Mac's `localhost`, so serve everything on the Mac's LAN address. Use a trusted network only: these development servers are unauthenticated.

```sh
IP=$(ipconfig getifaddr en0)   # Mac's LAN address; try en1 if empty
make supabase-start
make run-api API_HOST=0.0.0.0 ALLOWED_ORIGINS=http://$IP:3000                    # terminal 1
make build-web API_BASE_URL=http://$IP:8000 WEB_SUPABASE_URL=http://$IP:54321 \
  && make serve-web WEB_HOST=0.0.0.0                                             # terminal 2
echo "http://$IP:3000"         # open this URL in Safari on the iPhone
```

Allow incoming connections if macOS asks. Stop all servers and `make supabase-stop` when finished. This is plain HTTP for a local check; HTTPS, home-screen installation and updates are verified in Task 008. Step-by-step checks and results records: [Task 002 manual test](docs/manual-tests/002-auth.md) and [Task 001 manual test](docs/manual-tests/001-bootstrap.md).

## Repository inspection — 2026-10-11

The initial checkout contained only `.git`: no tracked files, application code, configuration, existing agent instructions, commits, or configured remotes. The unborn branch was `master`. Existing Git state has been preserved.

## Read in this order

1. [Product specification](docs/product.md): requirements, scope, validation.
2. [Domain model](docs/domain.md): ownership, invariants, lifecycle.
3. [Architecture](docs/architecture.md): boundaries, data paths, decisions requiring approval.
4. [MVP plan](docs/plans/001-mvp.md): ordered tasks and acceptance criteria.
5. [Engineering standards](docs/engineering-standards.md), [development](docs/development.md), and [deployment](docs/deployment.md).
6. [Risk register](docs/risks.md) and [architecture decisions](docs/adr/README.md).

[AGENTS.md](AGENTS.md) assigns Codex planning/review responsibilities; [CLAUDE.md](CLAUDE.md) assigns implementation responsibilities. The human owns scope, consequential decisions, approval, merges, and releases.

## Decision vocabulary

- **Confirmed requirement:** explicitly supplied by the product owner.
- **Assumption:** unconfirmed interpretation, recorded for correction.
- **Recommendation / Proposed:** reasoned design that is not approved.
- **Accepted:** explicitly directed constraint or subsequently recorded human approval; never inferred from silence.
- **Decision required:** consequential choice with an identified approval gate.

The requested stack is the planning baseline, not permission to implement or provision it. Newly proposed design details remain proposed. Record approval scope and date in the relevant ADR and task plan when received.
