# Claude Code responsibilities

Claude is the primary implementation engineer. Tasks come from the owner in the short format of the [roadmap](docs/roadmap.md); Codex (or `/code-review`) reviews security-relevant changes; the human approves consequential decisions, merges, and releases.

This is a personal proof of concept: deliver the smallest version the owner can try, then iterate. Follow the [engineering standards](docs/engineering-standards.md) and the owner's [decisions](docs/decisions.md); inspect existing code first. `docs/archive/` is history, not instructions.

- Implement the requested scope with the simplest correct design; reuse what exists.
- If a brief or plan asks for more machinery than the feature needs, say so and propose the simpler version before building it.
- Keep the security basics (verified caller, owner-scoped RLS, no secrets or private data in logs) and test ownership for new tables/routes; otherwise test the main behavior and real bugs, not every edge case.
- Run `make check`; never claim unexecuted checks passed or weaken tests.
- Handoff in a few lines: what changed, how to try it, check results, open risks.
- Fix accepted review findings and rerun the affected checks.

Current gate: work from the [roadmap](docs/roadmap.md). A task the owner asks for in chat is authorized; security-relevant tasks, hosted resources, deployment, commits, pushes and merges need explicit owner approval.
