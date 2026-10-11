# ADR 001 — Requested stack and simple topology

**Status:** Accepted as owner-supplied planning constraints, 2026-10-11. This records the user's direction, not approval of implementation, added dependencies, detailed security design or production provisioning.

**Task 001 approval (2026-10-11):** The human approved implementing Task 001 only (Flutter Web connectivity shell, FastAPI health endpoint, pinned bootstrap dependencies, `make check` and CI), with built-in Flutter state and Riverpod evaluation deferred to Task 002. This does not approve Task 002, provider configuration, hosting or production resources.

## Context

R7 needs a mobile web experience with future Flutter reuse; R4 needs managed private identity/data; R8 requires low operational complexity; R9 separates planning, implementation and human control. The repository was empty; there is no existing stack to migrate or deficiency to remedy.

## Decision

Plan a simple monorepo: Flutter/Dart mobile-first web and Material 3, Python/FastAPI modular monolith, Supabase PostgreSQL/Auth/Storage, server-side OpenAI integration and GitHub Actions. Prefer relational search initially. Keep the working product name out of business rules. No native builds or speculative infrastructure.

## Alternatives considered

A web-specific replacement would contradict the requested Flutter direction without an observed blocker. Self-managed identity/storage increases maintenance without an MVP requirement. Microservices and a monorepo framework add orchestration with no demonstrated need. None is recommended now.

## Consequences

Cross-language toolchains and Safari-specific validation are necessary. Flutter Web suitability must be demonstrated early; future native targets still need platform work. Managed providers create some coupling, contained by SQL migrations, portable sources and small integration modules. Riverpod, data-access semantics, hosting plans and model selection remain proposals. Any technology replacement requires evidence and approval.
