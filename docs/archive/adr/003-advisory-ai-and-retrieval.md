# ADR 003 — Advisory AI and grounded retrieval

**Status:** Proposed. Human approval required for AI processing/privacy/spend before live use.

## Context

R1/R6 require editable extraction without blocking manual saving. R5 requires owned saved ideas, factual limits and follow-ups. R8 rejects speculative vector infrastructure. Current approach: structured relational collection, no AI or retrieval implemented. Limitation: ordinary saved records alone cannot produce screenshot suggestions or conversational explanations.

## Decision proposed

Use a small server-side OpenAI adapter with schema-validated output and bounded requests. Keep drafts transient and save only after user confirmation. Retrieve with owner-scoped SQL/category filters/PostgreSQL text search, then pass a bounded candidate set to the model. Validate references/evidence server-side and show canonical item fields. Retain chat context only in active client memory and reauthorize every turn. Treat imported material as untrusted and give the model no tools for writes or external fetching. Preserve a manual/search fallback. Set explicit quotas and a human-approved monthly ceiling before live calls.

## Alternatives considered

Model-only retrieval cannot enforce ownership or prove saved items exist. Durable provider conversation state introduces retention and deletion complexity without an MVP need. Embeddings may improve semantic recall but are premature without failed representative retrieval cases; benchmark first. A generic provider/agent framework introduces more abstraction than two bounded operations require. No AI would preserve saving but miss the confirmed screenshot/conversation capability.

## Consequences

Lexical search may miss paraphrases; evaluation and safe broadening are needed. Structured output validates shape, not truth: evidence checking and adversarial cases remain necessary. Session reload loses chat. API processing has cost and provider retention implications even when application persistence is disabled. Model choice remains configurable and must be tested for German/English screenshots and recommendations. Native live facts and internet recommendations stay out of scope.

See [architecture](../architecture.md) for evaluation thresholds and official references. Approval record: pending.
