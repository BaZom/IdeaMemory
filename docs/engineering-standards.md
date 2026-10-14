# Engineering standards

This is a personal proof of concept. Match effort to risk: build the smallest version the owner can try, then iterate. Rigor goes where a mistake would leak private data or lose it, not into ceremony.

## Always

- Inspect the actual code before changing it; don't invent APIs, dependencies or settings.
- UI follows the [target design](design/oh-app.html) and the product principles in the [roadmap](roadmap.md); deviations need the owner’s OK.
- Keep changes focused and readable; reuse existing patterns; no speculative abstractions or frameworks.
- Security basics are not negotiable: verify the caller on every API request, never trust owner IDs from the client, owner-scoped RLS on every user table, no secrets in the repo or the app, no private content in logs.
- Data changes go through forward migrations; never reset or drop data the owner may want without asking.
- Never claim a check passed that was not run; never weaken tests to get a pass.

## Proportionality

- **Push back on over-engineering.** If a brief asks for more machinery than the feature needs (retry ledgers, state machines, exhaustive matrices, cross-layer contracts), propose the simpler version first and let the owner choose.
- **Tests:** cover the main behavior, ownership (one two-user isolation test per new table or route), and real bugs found. Not every edge case, not every layer twice.
- **Docs:** update the README/development guide when setup or behavior changes. No ADR unless the decision is hard to reverse (e.g. a new hosted service, a data model change other features depend on).

## Workflow

| Change | Workflow |
| --- | --- |
| Small (docs, copy, styling, small fixes) | Do it, run the relevant check, summarize |
| Feature | Short plan in chat or a few lines in the plan doc (goal, 2–4 acceptance criteria, what is out) → implement → `make check` → summary |
| Security-relevant (auth, data access/RLS, AI with personal data, deployment, destructive data change) | As a feature, plus explicit owner approval before starting and an independent review (Codex or `/code-review`) of the diff |

The handoff is short: what changed, how to try it, checks run with results, and anything risky or not done. The owner controls commits, merges and releases.

## Reviews

Reviews report only real problems, each with severity (P0 critical, P1 blocks release, P2 should fix, P3 minor), file/line, the problem and a fix. End with **APPROVE**, **APPROVE WITH MINOR FIXES** or **CHANGES REQUIRED**. Skip style points the tools already enforce. A review approval is not permission to merge or release.
