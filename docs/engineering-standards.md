# Engineering standards

## Shared rules

Inspect actual code and approved plans first. Verify uncertain library behavior against official documentation; do not invent APIs, fields, environment variables, or dependencies. Keep changes focused, explicit, and readable. Prefer simple control flow and meaningful names. Reuse patterns, avoid circular dependencies and duplicate layers; keep business logic independent of widgets and provider SDKs. Document non-obvious decisions rather than obvious code.

Validate all untrusted inputs and responses. Authorize every server resource operation; never trust owner IDs, model IDs, or storage keys from a client. No committed secrets, private payload logging, or weaker security to ease development. Use migrations, integrity constraints, and two-user isolation tests. Preserve existing data and obtain explicit approval for destructive migration or production-sensitive work.

Define consistent API errors, pagination and compatibility. Add tests for behavior, significant regressions, relevant edge/failure paths and authorization. Never delete/weaken tests to make a change pass. Run relevant format, lint, static/type checks, tests, and builds; record exact executed results and unavailable checks.

Before a significant dependency: identify the requirement, inspect existing solutions, evaluate maintenance, security, license, compatibility and cost. Routine small code does not justify a large framework. Every meaningful complexity increase needs a concrete requirement or measured limitation and a traceable decision.

## Proportional workflow

| Level | Trigger | Required workflow |
| --- | --- | --- |
| 1 — trivial | Docs, labels, isolated low-risk style | Inspect → authorized small change → relevant lightweight check → summary; no routine ADR/plan |
| 2 — standard | Feature, query, endpoint, nontrivial bug | Codex focused plan/criteria → approved scope → Claude implementation/tests → checks → Codex review → accepted fixes → CI → human merge/release |
| 3 — high impact | Auth, ownership, domain model, major dependency, architecture, destructive data or production change | Investigate motivation/alternatives/tradeoffs → explicit approval → plan/ADR status update → Claude implements/tests → architectural review → CI → human merge/release |

Risk overrides diff size. Existing approval covers routine choices; no repeated approval for ordinary in-scope details. Proposed ADRs do not authorize work. Approval of foundation documents does not automatically authorize every future task or production action.

## Plans and handoff

A substantial task records goal, scope/non-goals, dependencies, expected components, testable acceptance criteria, tests, risks and definition of done. Do not create a second plan when a concise update to the existing one suffices. Human approvals record scope/date; conflicts with an approved plan are reported before architecture is changed.

Claude's handoff summarizes changed files, criteria met, executed checks/results, limitations and remaining risks. Codex inspects the actual diff and relevant callers/tests, not only the handoff. Prioritize correctness, security, integrity, acceptance criteria, architectural consistency, maintainability and relevant cost/performance. Avoid subjective style findings already handled by tools.

## Review findings and outcome

Each actionable finding contains **Severity** P0/P1/P2/P3, **Location** file and line, **Problem**, **Impact**, and **Recommended Fix**. P0 is urgent critical failure; P1 blocks release due to serious impact; P2 is normal-priority corrective work (blocking when correctness/criteria demand it); P3 is a minor non-blocking issue. Do not fabricate findings.

End every implementation review with exactly one outcome:

- **APPROVE** — no blocking findings.
- **APPROVE WITH MINOR FIXES** — only non-blocking findings remain.
- **CHANGES REQUIRED** — blocking correctness, security, architecture or acceptance issues remain.

Report verification limits before the outcome. Reviewer approval is not authority to merge or release; those remain human-controlled.
