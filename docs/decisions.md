# Decisions

Owner decisions and the technical choices that follow from them. Newest first. Older reasoning is in the [archive](archive/README.md).

| Date | Decision | Consequence |
| --- | --- | --- |
| 2026-10-11 | Keep the project lightweight: short tasks, few tests, reviews only for security-relevant changes | [Engineering standards](engineering-standards.md), [roadmap](roadmap.md) |
| 2026-10-11 | Single-device use: the last save wins; no duplicate protection for retried saves | No edit-conflict checks or retry records |
| 2026-10-11 | Ideas are not marked done | No status field, control or filter |
| 2026-10-11 | Accounts are a username + password; no email, verification or recovery for now | Supabase Auth needs an email, so the app stores `<username>@users.invalid` (never shown, never receives mail). Revisit before inviting other people |
| 2026-10-11 | Fixed optional categories (food, activity, travel, film-series, recipe, product, book, place, other) and free tags | No category or tag management |

## Technical choices

- **Stack:** Flutter Web app (`apps/mobile`), FastAPI (`services/api`), Supabase for auth, database and (later) file storage; a local Supabase stack in Docker for development.
- **Privacy boundary:** the API verifies every request's token with Supabase and then talks to the database *as that user*, so database row-level security limits every query to the user's own rows. There is no admin key in the running app. Tokens signed with Supabase's shared legacy secret are refused, so a hosted project must use its asymmetric signing keys.
- **Original text** is stored separately from the editable fields and never changed.
- **Schema changes** are forward migrations in `supabase/migrations/`; existing data is kept.
