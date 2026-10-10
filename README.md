# Idea Memory

Working title: a private, conversational memory for things you want to experience.

**Status: Task 001 (project bootstrap) implemented locally, pending Codex review, remote CI and physical iPhone verification.** Task 001 was approved on 2026-10-11; Tasks 002–008 are not approved. No cloud resource, deployment, Supabase or OpenAI configuration exists.

The repository contains a Flutter Web connection-check shell (`apps/mobile/`), a FastAPI service with a `GET /health` liveness endpoint (`services/api/`), a root `Makefile` and a GitHub Actions workflow. See [development](docs/development.md) for setup, running and validation.

```sh
make setup   # pinned Python venv + locked Flutter packages
make check   # every canonical check; nonzero on any failure
make run-api # terminal 1: API on http://127.0.0.1:8000
make run-web # terminal 2: Flutter app on http://localhost:3000
```

### Run on an iPhone (same Wi-Fi)

An iPhone cannot reach the Mac's `localhost`, so serve both components on the Mac's LAN address. Use a trusted network only: these development servers are unauthenticated.

```sh
IP=$(ipconfig getifaddr en0)   # Mac's LAN address; try en1 if empty
make run-api API_HOST=0.0.0.0 ALLOWED_ORIGINS=http://$IP:3000                    # terminal 1
make build-web API_BASE_URL=http://$IP:8000 && make serve-web WEB_HOST=0.0.0.0    # terminal 2
echo "http://$IP:3000"         # open this URL in Safari on the iPhone
```

Allow incoming connections if macOS asks. Stop both servers (Ctrl+C) when finished. This is plain HTTP for a quick smoke check; HTTPS, home-screen installation and updates are verified in Task 008. Step-by-step checks and a results record are in the [Task 001 manual test](docs/manual-tests/001-bootstrap.md).

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
