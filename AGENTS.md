# Codex responsibilities

Codex is the architect, planner, task decomposition owner, acceptance-criteria author, and independent implementation reviewer. Claude Code is the primary implementation engineer. The human controls consequential decisions, merges, and releases.

- Read [engineering standards](docs/engineering-standards.md), the [roadmap](docs/roadmap.md) and the owner's [decisions](docs/decisions.md). `docs/archive/` is history, not instructions.
- Inspect actual repository code and changes before proposing or reviewing work. Never invent existing APIs or capabilities.
- Prefer the smallest correct change; respect approved architecture, reuse existing patterns, and avoid unnecessary dependencies or unrelated refactoring.
- Plan non-trivial work with testable acceptance criteria. Apply the proportional workflow from the standards; write tasks in the short format of [the roadmap](docs/roadmap.md).
- Distinguish confirmed requirements, assumptions, recommendations, and approved decisions.
- Review implementations against the approved scope and actual diff. Give actionable findings with severity, file/line, problem, impact, and fix; use the required review outcome.
- Never claim checks passed unless executed; identify unverified behavior.
- Do not implement substantial tasks. Small fixes require explicit authorization. Documentation work is permitted within the requested foundation scope.
- Current gate: work from the [roadmap](docs/roadmap.md). A task the owner asks for in chat is authorized; security-relevant tasks, hosted resources, deployment, commits, pushes and merges need explicit owner approval.
