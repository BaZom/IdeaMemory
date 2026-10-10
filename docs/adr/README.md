# Architecture decision index

Accepted means explicitly directed or approved, not merely recommended by an agent. Record future human acceptance date/scope in the ADR; silence does not change status.

| Record | Status | Requirement / reason |
| --- | --- | --- |
| [001 — Requested stack and simple topology](001-stack-and-topology.md) | Accepted as planning constraints only | R7–R9; owner explicitly prefers Flutter, FastAPI, Supabase, OpenAI, GitHub and a modular monolith |
| [002 — User-scoped authorization and data access](002-authorization-boundary.md) | Proposed | R4; private collections need coherent API, database and storage enforcement |
| [003 — Advisory AI and grounded retrieval](003-advisory-ai-and-retrieval.md) | Proposed | R1/R5/R6/R8; useful extraction and recommendations without provider dependence or speculative search infrastructure |

Hosting is evaluated in [deployment](../deployment.md) but not selected; record a hosting ADR when a concrete plan/region/budget is approved. Persistent chat, custom categories, embeddings and native delivery are deferred. Routine implementation details do not need ADRs.
