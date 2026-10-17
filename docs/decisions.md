# Decisions

Owner decisions and the technical choices that follow from them. Newest first. Older reasoning is in the [archive](archive/README.md).

| Date | Decision | Consequence |
| --- | --- | --- |
| 2026-10-17 | **A calmer first page and soft answers**: spaces are tabs (not story circles); suggestions are a deck of cards (right = yes, left = *Another time*); *Another time* replaces “Not for me” and “Not now” and is never a hard no; matches, waiting and worth knowing are one line each; Remember is a round + | Votes are “yes” or “later” (with when it comes back), plus a private “hidden for me”; matches count only yeses |
| 2026-10-15 | **Couples and groups are a core feature**: shared spaces (2–8 people) with one memory, “I’d love to / Another time” with matches, and plans made together (find a day, who’s in, who sorts out what, short notes, invite links for people without the app). Spaces are visible on the first page; signup asks “Who do you do things with?”. Replaces “sharing is later” | Roadmap phase 2 (014–017) comes before AI; memories belong to a space from 011; access follows space membership. No in-app chat, no public profiles, no groups over 8 |
| 2026-10-15 | The app is called **Oh, right!** (tagline “your little memory”); “oh,” is the icon and logo mark | Visible name, icon and docs use it; the repository and code names stay as they are. Before going public (014): check App Store, Google Play, trademarks (TMview, classes 9 and 42) and a domain |
| 2026-10-14 | Product principles: the nudge recommends from your memory for today or very soon; My memory holds everything; plans come from memories; saving asks little and infers a lot | [Roadmap](roadmap.md) principles and main flow; every task is checked against them |
| 2026-10-14 | Target design is “oh! your little memory”, now branded Oh, right! ([oh-app.html](design/oh-app.html)) with three tabs: A little nudge, Planned, My memory (Our memory in a shared space) | UI tasks build towards it; deviations need the owner’s OK |
| 2026-10-14 | Plans are always a day (tonight, tomorrow, this weekend, a picked day), one active plan per memory; a passed plan becomes a “planned before” line | No done status, no “still want to?” prompt, no “someday” list |
| 2026-10-14 | ~~Sharing is later and starts as an invite link with “I’m in / Maybe”~~ (replaced on 2026-10-15 by couples and groups); still no in-app chat | The invite link for people without the app stays, as part of 017 |
| 2026-10-14 | AI comes in phase 2: first “fill it in for me”, then “ask your memory”; suggestions stay rule-based at first | See [roadmap: when AI comes in](roadmap.md#when-ai-comes-in-and-why) |
| 2026-10-14 | Kinds are a small fixed list (food, places, films and shows, books, things to do, trips, events, music, other), filled in automatically where possible; personal tags for anything finer | Kinds drive icons and browsing; tags are free |
| 2026-10-11 | Keep the project lightweight: short tasks, few tests, reviews only for security-relevant changes | [Engineering standards](engineering-standards.md) |
| 2026-10-11 | Single-device use: the last save wins; no duplicate protection for retried saves | No edit-conflict checks or retry records |
| 2026-10-11 | Ideas are not marked done | No status field, control or filter |
| 2026-10-11 | Accounts are a username + password; no email, verification or recovery for now | Supabase Auth needs an email, so the app stores `<username>@users.invalid` (never shown, never receives mail). Recovery must be decided in 014, before partners and friends join |

## Architecture

```text
 Flutter web app (phone-first, later installable)
        │  HTTPS, the user's own access token
        ▼
 FastAPI service ── verifies the token with Supabase Auth on every request
        │  acts as that user (no admin key)            │ phase 3+, server only
        ▼                                              ▼
 Supabase: Postgres with row-level security      AI provider (approved model,
 (spaces, members, memories, plans), Auth,       minimal text, no account data)
 Storage (phase 4)
```

- **Access follows the space.** Every memory belongs to a space; you see and change a space’s memories and plans only while you are a member. *Just me* is a space with one member, so personal and shared data use the same rule. The database itself enforces it (row-level security on membership, plus column grants); the API also filters by the verified user. Today’s code still has one owner per row; 011 adds spaces, 015 adds members.
- **Your answers are yours.** Votes, “I’m in” answers and notes are stored per member; only you can change your own; others see a vote only after they have answered.
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
| Another time (012) | Sets `snoozed_until` (a few days ahead) on the memory, so it holds across devices. In shared spaces see 016. |
| Plans (013) | A `plans` table in the memory’s space: memory reference (same owner enforced by the database), day, optional time, reminder choice, where, people (names), a short checklist, what to bring. A plan is active while its day is today or later; at most one active plan per memory (checked by the API). Past plans stay as rows and show as “planned before”. |
| Reminders (013, 014) | In the app first (Planned, “worth knowing”); real notifications come with hosting and installation (014). |
| Spaces (011, 015) | `spaces` (name, kind: personal or shared) and `space_members` (space, user, role owner/member). Each account gets a personal space at signup; memories get `space_id`. RLS: a row is visible to members of its space only. Joining via an unguessable, revocable invite token checked in a security-definer function that only adds the caller. Up to 8 members. |
| Say yes together (016) | `memory_votes` (memory, member, `yes` or `later`, `back_after` date for later, `later_count`, unique per member) and a private `hidden_for_me` flag only its owner can read. Others’ votes are returned only once you answered. *Later* comes back after `back_after` (a few weeks), sooner when someone else says yes. Match: only yeses count; all members for two, the caller plus more than half for groups; computed in the API. News counts: compare items with your `last_seen_at` per space. |
| Plan together (017) | `plan_answers` (plan, member, in/maybe/out), `plan_day_options` + votes, `plan_todos.assignee`, `plan_notes` (short text, author). Updates by polling first (no realtime service). Guest link: an unguessable token showing a read-only plan card; guests give a name and an answer, no account; the owner can turn it off. |
| Save from a link (018) | The server fetches the page: http(s) only, no private or local addresses (checked after DNS resolution and on every redirect), small size and time limits, no cookies. Reads the page title, Open Graph data and schema.org event dates. The app never fetches pages itself. |
| Fill it in for me (019) | One server-side AI call per save with the link text and your note; the answer must fit a fixed schema (kind, moods, tags, dates) and is shown as suggestions you confirm. Off switch and budget limit; the app works without it. |
| Ask your memory (020) | Retrieval over the current space’s memories only (database search, embeddings if needed), then one AI call that may only use the retrieved memories and must cite them. If nothing matches it says so. |
| Screenshots (021) | Private Storage bucket with the same space rules; deleting a memory deletes its image. |
