# Decisions

Owner decisions and the technical choices that follow from them. Newest first. Older reasoning is in the [archive](archive/README.md).

| Date | Decision | Consequence |
| --- | --- | --- |
| 2026-10-14 | Product principles: the nudge recommends from your memory for today or very soon; My memory holds everything; plans come from memories; saving asks little and infers a lot | [Roadmap](roadmap.md) principles and main flow; every task is checked against them |
| 2026-10-14 | Target design is “oh! your little memory” ([oh-app.html](design/oh-app.html)) with three tabs: A little nudge, Planned, My memory | UI tasks build towards it; deviations need the owner’s OK |
| 2026-10-14 | Plans are always a day (tonight, tomorrow, this weekend, a picked day), one active plan per memory; a passed plan becomes a “planned before” line | No done status, no “still want to?” prompt, no “someday” list |
| 2026-10-14 | Sharing is later and starts as an invite link with “I’m in / Maybe”; no in-app chat | No shared ownership of rows in the MVP |
| 2026-10-14 | AI comes in phase 2: first “fill it in for me”, then “ask your memory”; suggestions stay rule-based at first | See [roadmap: when AI comes in](roadmap.md#when-ai-comes-in-and-why) |
| 2026-10-14 | Kinds are a small fixed list (food, places, films and shows, books, things to do, trips, events, music, other), filled in automatically where possible; personal tags for anything finer | Kinds drive icons and browsing; tags are free |
| 2026-10-11 | Keep the project lightweight: short tasks, few tests, reviews only for security-relevant changes | [Engineering standards](engineering-standards.md) |
| 2026-10-11 | Single-device use: the last save wins; no duplicate protection for retried saves | No edit-conflict checks or retry records |
| 2026-10-11 | Ideas are not marked done | No status field, control or filter |
| 2026-10-11 | Accounts are a username + password; no email, verification or recovery for now | Supabase Auth needs an email, so the app stores `<username>@users.invalid` (never shown, never receives mail). Revisit before inviting other people |

## Architecture

```text
 Flutter web app (phone-first, later installable)
        │  HTTPS, the user's own access token
        ▼
 FastAPI service ── verifies the token with Supabase Auth on every request
        │  acts as that user (no admin key)            │ phase 2+, server only
        ▼                                              ▼
 Supabase: Postgres with row-level security      AI provider (approved model,
 (memories, plans), Auth, Storage (phase 3)      minimal text, no account data)
```

- **One owner per row.** Every memory and plan belongs to exactly one user; the database itself refuses anything else (row-level security plus column grants). The API also filters by the verified user.
- **Business rules live in the API**, so the app stays a display layer: what the nudge suggests, what is “worth knowing”, when a plan becomes history.
- **Schema changes** are forward migrations in `supabase/migrations/`; existing data is kept.
- **Original text** saved with a memory is stored separately and never changed.
- **Tokens signed with Supabase’s shared legacy secret are refused**, so a hosted project must use asymmetric signing keys.

## Technical decision per feature

| Feature (task) | Decision |
| --- | --- |
| Memories (011) | Extend the existing `ideas` table rather than a new one: kind (the design’s list; migrate travel → trips, film-series → films and shows, recipe → food, product → other), `moods` (up to three fixed values), `who` (free text name), `tags` (exists), link (URL, site, title), `event_start`/`event_end` dates, `snoozed_until`. All optional except the title. |
| My memory (011) | Search runs in the database over the user’s own rows (title, note, who, location, link title, tags); browse rows are plain filters; shelves are computed from dates. No extra tables. |
| A little nudge (012) | Rule-based in the API: candidates are memories without an active plan, without own dates, not multi-day, not snoozed; ordered by how long they have waited. “Worth knowing” = plans in the next 3 days, events ending within 3 weeks, events starting within 3 weeks; at most three. Every item carries a short reason. |
| Not now (012) | Sets `snoozed_until` (a few days ahead) on the memory, so it holds across devices. |
| Plans (013) | A `plans` table owned like memories: memory reference (same owner enforced by the database), day, optional time, reminder choice, where, people (names), a short checklist, what to bring. A plan is active while its day is today or later; at most one active plan per memory (checked by the API). Past plans stay as rows and show as “planned before”. |
| Reminders (013, 019) | In the app first (Planned, “worth knowing”); real notifications come with hosting and installation (019). |
| Save from a link (014) | The server fetches the page: http(s) only, no private or local addresses (checked after DNS resolution and on every redirect), small size and time limits, no cookies. Reads the page title, Open Graph data and schema.org event dates. The app never fetches pages itself. |
| Fill it in for me (015) | One server-side AI call per save with the link text and your note; the answer must fit a fixed schema (kind, moods, tags, dates) and is shown as suggestions you confirm. Off switch and budget limit; the app works without it. |
| Ask your memory (016) | Retrieval over your own memories only (database search, embeddings if needed), then one AI call that may only use the retrieved memories and must cite them. If nothing matches it says so. |
| Screenshots (017) | Private Storage bucket per user with the same ownership rules; deleting a memory deletes its image. |
| Sharing (later) | An unguessable invite link to a read-only plan card with “I’m in / Maybe”; answers are stored on the plan. No accounts for guests, no chat. |
