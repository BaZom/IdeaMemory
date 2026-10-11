# ADR 002 — User-scoped authorization and data access

**Status:** Accepted for Task 002 scope on 2026-10-11 (human instruction to implement Task 002 after its proposed decisions were summarized; see the [Task 002 brief](../plans/001-mvp.md#task-002--authentication-and-private-access)). Updated by subsequent explicit owner decisions on 2026-10-11: self-service in-app signup is required (invite-only superseded); then, after trying email codes and email + password, accounts are **username + password with no email address** (see “Account identity” below). Later storage, domain and hosted-environment details remain subject to their own task approvals.

## Context

R4 requires each user's collection, images and retrieval to stay private. A public mobile web client is untrusted. Supabase publishable credentials do not restrict clients to the intended FastAPI route, and privileged credentials can bypass RLS. Current approach: the requested managed stack, with no implemented access path. Limitation: ownership cannot be guaranteed until one coherent path and independently effective policies are defined.

## Decision proposed

Use direct Supabase Auth from Flutter, self-service username + password signup and sign-in, and FastAPI for application operations. For Task 002, verify each bearer token online using the configured Supabase Auth user endpoint, enforcing expected user claims and matching the provider-returned identity. Use that user's bearer token for Supabase Data API and Storage. Enforce owner-scoped RLS, constraints and grants; security-invoker SQL functions provide multi-row transactions. Test direct-provider bypass attempts. Privilege is confined to explicit operator cleanup/account procedures, never normal requests. Source images live in private buckets with short-lived authorized access.

## Task 002 implementation clarification

The prepared task proposes online server-side token verification first, not a local JWKS cache: supported provider verification handles signatures and signing-key changes, while the API checks the expected user identity/claims and fails closed on outages. This adds per-request latency and Auth availability dependence but avoids maintaining a second verification mode. Do not build custom cryptography or trust decoded claims alone. Access tokens remain request-local; shared mutable SDK auth state is prohibited.

Flutter uses managed SDK session persistence and a small built-in state controller; Riverpod remains deferred. Provide visible Sign up and Sign in choices. Anonymous sign-in remains disabled. Local synthetic users may be provisioned through an operator-only admin path for isolated fixtures; normal users never need that path. No hosted resources are part of this approval. See [Task 002](../plans/001-mvp.md#task-002--authentication-and-private-access) for the contract, test scope and explicit approval instruction.

## Account identity (owner decision, 2026-10-11)

Accounts are a username and a password. Supabase Auth requires an email, so the app maps each normalised username to the placeholder address `<username>@users.invalid` (reserved domain that can never receive mail); users never see it. Email confirmation is off, so sign-up returns a session immediately. The owner explicitly deferred account recovery and email/contact verification for the current MVP, reaffirmed after review on 2026-10-11. Unchanged: online token verification, per-user RLS and private Storage, and the isolation tests. Earlier variants (email OTP; email + password) were implemented and superseded the same day; a database trigger added for the OTP variant was removed before any commit. Revisit recovery and verification before inviting real users (Task 008).

## Superseded product restriction

Invite-only/operator-created accounts were an incorrect interpretation of initial personal testing. The product owner explicitly requires self-service account creation for multiple users. This correction replaces that restriction without weakening server-side identity, row ownership, private Storage or token validation. Registration stays with the managed provider; no custom registration infrastructure.

## Alternatives considered

Service-role access for every API request is simple but turns one missing owner predicate into unrestricted exposure; reject as default. Local asymmetric JWT verification could avoid a network call but introduces key caching/rotation logic; defer until measured latency or availability justifies it. Direct SQL with a dedicated non-bypass role and transaction-local identity offers flexibility but adds connection/identity plumbing. Direct frontend domain writes reduce API code but spread validation and orchestration across clients, contrary to requested backend responsibilities. HttpOnly backend session mediation reduces token access from browser scripts but adds a separate session boundary; reconsider if pilot threat assessment demands it.

## Consequences

The API and provider policies both require isolation tests. RPC adds limited Supabase coupling but keeps data transactional and SQL portable. Browser token persistence needs careful script/CSP hygiene. Normal runtime does not need a service-role secret. Cleanup still needs constrained operational privilege and a clear audit trail. Detailed grants, token verification and storage policy behavior must be proven in Task 002/005, not assumed from this ADR.

Reference: [Supabase RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security). Approval record: Task 002 scope approved 2026-10-11; self-service signup and then username + password accounts explicitly required by the product owner the same day. Implementation evidence is in the Task 002 progress notes, not this document.
