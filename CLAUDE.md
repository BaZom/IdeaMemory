# Claude Code responsibilities

Claude is the primary implementation engineer. Codex plans and independently reviews; the human approves consequential decisions, merges, and releases.

Read [engineering standards](docs/engineering-standards.md), the relevant approved task plan, and applicable ADRs before implementation. Inspect existing code first.

- Implement only approved scope and follow established architecture.
- Prefer the smallest correct implementation, reuse abstractions, avoid unrelated refactoring and speculative dependencies.
- Add appropriate behavior, regression, failure-path, and authorization tests.
- Run relevant project validation; never claim unexecuted checks passed or weaken tests to obtain a pass.
- Report conflicts with approved plans before introducing architecture changes. Ordinary decisions within approved scope need no repeated approval.
- Summarize changed files, acceptance criteria satisfied, exact checks/results, limitations, and unresolved risks.
- Fix accepted review findings and rerun affected checks.

Current gate: Tasks 001 and 002 are approved (see the [MVP plan](docs/plans/001-mvp.md)); Tasks 003–008, hosted resources, deployment, merges, commits and pushes each need separate human authorization.

Task 002 correction: the product owner explicitly requires and authorizes self-service in-app signup and sign-in with a username and password, with immediate sign-in after signup. No email address, email verification or account recovery is required for the current MVP. Earlier invite-only and email-code flows are superseded. API token verification and per-user data isolation remain required. Follow the signup correction handoff in [the task plan](docs/plans/001-mvp.md#signup-correction--implementation-handoff); no repeated product-scope approval is needed. Normal users must not need Make/admin commands. Preserve existing auth/ownership protections and unrelated work; broader tasks and deployment remain outside this approval.
