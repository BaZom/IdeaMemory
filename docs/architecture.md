# Proposed architecture

Status: planning recommendation; [ADRs](adr/README.md) distinguish the requested baseline from new decisions. Requirements refer to [product](product.md).

## System and data paths

```text
Flutter Web / PWA ── sign-in / refresh / logout ──> Supabase Auth
       |
       └── bearer access token ──> FastAPI modular monolith
                                     ├── user-scoped Data API / SQL RPC ──> PostgreSQL + RLS
                                     ├── user-scoped Storage API ──> private images
                                     └── bounded extraction/recommendation ──> OpenAI
```

R1–R8 justify one Flutter app, one Python API, and managed data/auth/storage. No microservices, Redis, queues, event bus, Kubernetes, vector database, or generic agent framework. Explicit domain logic and small integration modules are sufficient.

## Authentication and authorization proposal — ADR 002

Flutter uses the official Supabase Flutter auth client for email OTP and session refresh. Invite-only pilot is recommended: disable unrestricted signup at the provider, provision invited identities through the operator, and test that non-invited users cannot create accounts by calling Auth directly. No custom passwords/session system. Tokens remain managed by the client SDK; browser persistence has an XSS exposure tradeoff, so avoid third-party scripts, use a restrictive tested CSP, and clear private application state on logout. HttpOnly backend session mediation would add a second auth/session boundary and is deferred unless the threat assessment requires it.

For Task 002, FastAPI uses online Supabase Auth user/token verification and enforces expected issuer, audience, expiry and subject matched to the verified user. Provider verification handles signatures and keys; fail closed on invalid identity or provider outage. No local JWKS cache or second verification mode is proposed initially. This adds request latency and an Auth availability dependency; evaluate local asymmetric verification later only against an observed limitation. Do not merely decode JWTs. The server derives ownership from the verified subject and scopes every lookup/mutation.

Recommended initial database path: FastAPI calls Supabase Data API with the user's verified bearer token and publishable project key. RLS applies per owner for SELECT/INSERT/UPDATE/DELETE, including `WITH CHECK` for mutations. Use security-invoker SQL RPC only when a multi-row transaction is needed (idea/source save, upload attachment, version checks). SQL migrations own functions and constraints. Avoid broad security-definer functions; any necessary privileged function requires a narrow reviewed contract and fixed search path. No ORM or separate direct database connection layer initially.

The browser architecture uses FastAPI for domain operations, but a publishable key and user token can call Supabase endpoints directly. Therefore RLS, constraints and grants must enforce ownership and valid states independently of API code. Revoke direct writes to sensitive upload/deletion bookkeeping; expose only the minimal validated user-scoped operations necessary. Test bypass attempts through Data API and Storage, not only FastAPI. Anonymous access to private rows is denied. Service-role credentials bypass RLS and must not be used for normal user requests. A separately configured operator cleanup path may hold privilege; it is never an HTTP user-facing credential or frontend setting.

This choice minimizes duplicated credentials and makes database authorization testable. Compared with direct SQL using a dedicated non-bypass role and transaction-local identity, it adds some PostgREST/RPC coupling. Standard SQL migrations and a narrow data-access module keep migration possible. Do not implement both alternatives.

## Flutter boundaries

Feature-oriented modules: auth, capture, collection, idea detail, chat; shared theme/widgets and a small typed REST client. Widget presentation is separate from async state and data access. Use built-in Flutter state for Task 001’s single connectivity interaction. Evaluate Riverpod without code generation in Task 002, when authentication and later capture introduce shared asynchronous state; the dependency remains proposed. Avoid repository/use-case/interface layers for every operation. Core models do not import platform-specific APIs. Future native uploads/sharing need explicit adapters when implemented; reuse is plausible, zero migration effort is not promised.

## Backend boundaries

- `auth`: verified identity dependency and auth errors.
- `ideas`: validated idea operations, owner-scoped data access and save transaction.
- `sources`: source attachment, upload lifecycle and private access.
- `extraction`: bounded URL fetching and HTML metadata parsing; cannot execute arbitrary tools.
- `ai`: a small provider adapter for structured suggestions and grounded answers, configured model/timeouts/budgets.
- `recommendations`: owner-scoped retrieval, bounded context and reference validation; owns selection, not the model.

Use plain functions and Pydantic schemas until state or shared behavior justifies a class. Routes delegate meaningful multi-step logic; no compulsory service class per endpoint. The OpenAI SDK stays inside `ai`; search SQL stays in data-access code. No autonomous agent loop.

## REST contract outline

Proposed `/api/v1`: idea list/create/detail/edit/delete; source attach/delete; URL extraction; image upload/extraction; recommendations. Auth endpoints remain Supabase-managed. Task plans must define exact schemas before implementation, not guess them from this outline.

Use bounded input sizes, response models, UTC ISO timestamps, UUID IDs, and opaque cursor pagination with stable `(created_at, id)` ordering and a maximum page size. Collection query accepts text/category/status. Save request includes the reviewed idea and original source references, never an authoritative owner ID. POST creation supports an owner-scoped retry key; PATCH includes expected version. External IDs/keys are always reauthorized.

Consistent error envelope: `{error: {code, message, request_id, field_errors?}}`; no stack traces, credentials or private provider messages. 401 invalid session, 404 absent or foreign-owned resource, 409 version conflict, 413 too large, 422 invalid input, 429 quota, 502/503 provider unavailable. Extraction warnings permit editing rather than pretending that enrichment succeeded. A deletion waiting for object cleanup returns an explicit pending state (e.g. 202), never a false claim of completed erasure. Logs include request IDs, timings, status and token totals, not URLs with query secrets, images, notes or chat bodies.

## URL capture and SSRF

Never fetch arbitrary URLs with an unrestricted HTTP helper. Proposed defaults: only HTTP/HTTPS on standard ports, no URL credentials, 10-second total deadline, at most 3 redirects, at most 2 MiB decompressed HTML. Validate parsed host and every resolved IPv4/IPv6 address; reject loopback, private, link-local, multicast, reserved and cloud metadata targets. Disable automatic redirects; validate and resolve every hop. Bind connection to an approved resolved address while preserving TLS hostname validation to prevent DNS rebinding. Reject mixed public/private DNS answers and enforce limits while streaming/decompressing. If the chosen client cannot provide the protection, fail extraction and allow manual saving until a safe fetch implementation is available.

Parse HTML metadata without JS execution, browser automation, downloads or authenticated scraping. Do not fetch preview images automatically; remote media brings the same SSRF/tracking risk. Retain bounded metadata and source URL; render all text as text, never raw imported HTML. Safe URL opening permits HTTP/HTTPS only. Failed extraction cannot block a user-confirmed manual title. [OWASP SSRF guidance](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html) informs address and redirect defenses.

## Image capture and cleanup

Proposed limits: JPEG/PNG/WebP, 10 MiB input, 20 megapixels decoded; reject SVG/animated/unsupported formats, inconsistent signatures and decompression bombs. Validate decoded content, not filename or claimed MIME. Preserve the validated original in a private bucket; use a resized metadata-stripped derivative for AI if useful. Unsupported HEIC gets an actionable format message; assess real iPhone screenshot samples early.

Stream bounded uploads through FastAPI to private Storage using owner-scoped credentials. Opaque owner-prefixed keys are not authorization. API and storage policy validate ownership/state; bucket restrictions backstop type/size constraints. Do not allow arbitrary object attachment. View via a short-lived signed URL issued after authorization, proposed 60-second expiry; treat it as a bearer secret and never log it. For deletion-sensitive UI, proxy authenticated reads if expiry is insufficient. Original object access stops after removal, though already downloaded copies cannot be recalled. [Supabase private buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals) document authorized downloads and expiring links.

Temporary upload bookkeeping and reconciliation in [domain](domain.md) are necessary because storage and PostgreSQL do not share a transaction. No background AI job service. Enrichment uses bounded foreground requests; manual saving remains available on timeout. Do not automatically retry chargeable AI calls on every widget rebuild.

## AI and retrieval — ADR 003

Use server-side OpenAI Responses API with a compatible image/text model selected against a small fixture set in Tasks 004–005. No model or price commitment yet. Request structured outputs, validate schema, lengths, enums and IDs; handle refusals, truncation and invalid output. Schema conformance does not establish factual truth. [Official structured output guidance](https://developers.openai.com/api/docs/guides/structured-outputs) is the implementation reference.

Send only the relevant source or bounded candidate records. Treat source text, images, notes, chat turns and model output as untrusted data, never executable instructions. No model network tools, SQL, writes, or arbitrary resource lookup. Use `store: false` where supported and send bounded session context explicitly; this does not guarantee zero provider retention. Review account-specific controls and disclosures before real personal data is sent. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data) distinguish application state and other retention.

Retrieval: authenticated owner constraint first; explicit category/status/text filters; PostgreSQL full-text search across title, description, tags, notes and location. Begin with language-neutral `simple` configuration for mixed German/English content, measured against pilot queries. Use GIN for search and owner/time indexes; benchmark before adding indexes indiscriminately. Category intent and a validated query rewrite may use bounded AI, but never model-generated SQL. For broad “surprise me” or “forgotten” requests use a bounded eligible sample or older saved records. For zero text results offer a clearly labeled broader collection match, not an assertion that a match satisfies unknown constraints.

Send at most a proposed 20 candidates and the last 6 bounded turns; model returns candidate idea IDs plus explanations/evidence fields. Re-fetch referenced IDs under current ownership and deletion state before responding; reject unknown or out-of-candidate IDs. Build links from server IDs. An owned ID alone does not prove a factual claim: use canonical fields for displayed facts and validate evidence references; unsupported price/location/availability claims must be omitted or marked unknown. Qualitative inference is labeled. Adversarial evaluations remain necessary; prompting alone is not a guarantee.

Session history is client memory only, reset on logout/reload; treat supplied historical IDs as untrusted and reauthorize. Never reuse a cross-user candidate cache. On provider failure show the owned search results as a clearly non-conversational fallback.

Measure retrieval on at least 20 curated German/English cases including follow-ups and empty matches. Proposed trigger for semantic-search investigation: fewer than 80% of answerable cases include a relevant item in top 5 after fixing basic query/category handling. Any expansion needs a benchmark and ADR; consider PostgreSQL extensions before a dedicated vector service.

## Costs, limits, availability

Before AI-capable pilot: proposed limits 20 AI requests/user/day, 5/minute, one concurrent extraction/user, 100 MiB stored uploads/user, bounded output tokens and request timeout. Values are tunable recommendations subject to the approved spend ceiling. Enforce quota reservations atomically in PostgreSQL so concurrent requests/multiple workers cannot bypass them; this small quota ledger contains counts, not private content. Release failed reservations under defined rules and record actual usage. Provider budget alerts complement, not replace, app-side caps. Manual CRUD remains available after AI limits. Retry at most once for transient errors within deadline; never blindly repeat a save or chargeable request.

## Mobile/PWA and testing

HTTPS manifest/icons/start URL and physical iPhone home-screen installation must be tested. Flutter does not currently generate/manage a caching service worker by default; see [Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq). Do not promise offline features. If a selected target requires a service worker, cache only public shell assets, version it and test upgrades; never cache private API responses, images or tokens. Verify keyboard/focus, safe areas, back navigation, upload picker, slow-network states and logout on actual Safari. An automated Chromium build is insufficient.

Unit tests cover parsing/domain/retrieval; API integration tests cover validation/ownership/failures; local Supabase tests exercise migrations, RLS, RPC and private storage using two distinct users; Flutter widget tests cover draft review/fallback; integration/manual checks cover the complete mobile workflow. Fake provider responses in CI; deliberate live AI evaluations require an approved budget.

## Decisions required and gates

| Package | Recommendation and tradeoff | Approval timing |
| --- | --- | --- |
| Implementation foundation | Requested stack and minimal module layout; built-in Flutter state for bootstrap, Riverpod evaluation deferred to Task 002 | Before Task 001; implementation permission is separate from documentation approval |
| Identity and data boundary | Invite-only email OTP; user-token Data API + RLS/RPC, private Storage; less privilege but some vendor coupling and browser token exposure | Before Task 002 (ADR 002) |
| MVP behavior/lifecycle | Fixed optional categories, free tags, saved/done, ephemeral chat, 24-hour abandoned uploads; simpler but no custom taxonomy/history recovery | Before Tasks 003/005/007 as applicable |
| AI privacy/spend | Bounded server-side processing, provider retention disclosure, explicit monthly ceiling chosen by owner | Before real AI/personal data use (ADR 003) |
| Deployment | Cloudflare Pages + paid Render in an appropriate EU region + Supabase; recurring cost buys steadier availability | Before Task 008 provisioning/release; exact plans, regions and cost require approval |

Unspecified budget is not permission to incur spend. Native builds, embeddings, custom categories, durable chat and broader scale are deferred. ADRs record human acceptance when supplied, not when drafted.
