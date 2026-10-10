# ADR 002 — User-scoped authorization and data access

**Status:** Proposed. Human approval required before Task 002. No security configuration exists yet.

## Context

R4 requires each user's collection, images and retrieval to stay private. A public mobile web client is untrusted. Supabase publishable credentials do not restrict clients to the intended FastAPI route, and privileged credentials can bypass RLS. Current approach: the requested managed stack, with no implemented access path. Limitation: ownership cannot be guaranteed until one coherent path and independently effective policies are defined.

## Decision proposed

Use direct Supabase Auth from Flutter, invite-only email OTP for pilot, and FastAPI for application operations. Verify identity at the API; use that user's bearer token for Supabase Data API and Storage. Enforce owner-scoped RLS, constraints and grants; security-invoker SQL functions provide multi-row transactions. Test direct-provider bypass attempts. Privilege is confined to explicit operator cleanup/account procedures, never normal requests. Source images live in private buckets with short-lived authorized access.

## Alternatives considered

Service-role access for every API request is simple but turns one missing owner predicate into unrestricted exposure; reject as default. Direct SQL with a dedicated non-bypass role and transaction-local identity offers flexibility but adds connection/identity plumbing. Direct frontend domain writes reduce API code but spread validation and orchestration across clients, contrary to requested backend responsibilities. HttpOnly backend session mediation reduces token access from browser scripts but adds a separate session boundary; reconsider if pilot threat assessment demands it.

## Consequences

The API and provider policies both require isolation tests. RPC adds limited Supabase coupling but keeps data transactional and SQL portable. Browser token persistence needs careful script/CSP hygiene. Normal runtime does not need a service-role secret. Cleanup still needs constrained operational privilege and a clear audit trail. Detailed grants, token verification and storage policy behavior must be proven in Task 002/005, not assumed from this ADR.

Reference: [Supabase RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security). Approval record: pending.
