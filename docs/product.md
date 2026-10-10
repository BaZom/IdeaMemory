# Product specification

## Vision and users

“Never forget the things you wanted to experience.” Discoveries scattered across social platforms, websites, messages, screenshots, and conversations should become useful personal memory. The experience should be effortless, personal, and conversational, without project-management forms.

Confirmed audience: the product owner first, then a small invited group, each with a separate private collection. The only application role is an authenticated collection owner. An unauthenticated visitor can authenticate but cannot inspect collections. The operator is an operational responsibility, not an MVP admin UI or permission hierarchy.

## Requirement register

| ID | Confirmed requirement | Observable outcome |
| --- | --- | --- |
| R1 | Capture manual text, URL, and screenshot | Each produces an editable draft and saves on explicit confirmation |
| R2 | Preserve idea and source separately | Saved idea opens its original URL/image; manual idea needs no external source |
| R3 | User-controlled organization | Browse, search, category filter, edit, delete, tags, notes, status; category optional |
| R4 | Private accounts | Managed auth, secure sessions, server authorization; no cross-user access |
| R5 | Grounded conversational rediscovery | Follow-ups recommend existing owned ideas and acknowledge missing facts |
| R6 | AI is advisory and optional for saving | Suggestions are editable; provider/extraction failures do not block manual saving |
| R7 | Mobile web / PWA | Core workflow works in iPhone Safari; installation where supported |
| R8 | Simplicity and portability | Modular monolith, relational data, exportable originals, no speculative infrastructure |
| R9 | Human-controlled engineering | Codex plans/reviews, Claude implements approved scope, human merges/releases |

## Core workflow and screens

Discover → add text/URL/image → bounded processing → review suggestions and original source → edit → confirm save → browse collection → later ask assistant → refine conversationally → open idea and source.

Conceptual views: assistant/home, add idea, collection, detail/edit, chat, and authentication. Home and chat may share one view; no mandated navigation hierarchy. Material 3 tokens, readable text, labeled touch targets, keyboard and screen-reader access, visible loading/cancel/retry states, and responsive layouts guide implementation.

## MVP scope

Email authentication; private accounts; manual CRUD; safe best-effort URL metadata; private screenshot upload and multimodal suggestions; optional categories/tags/notes; basic status; search and filters; source display; session conversation; references to saved items. Preserve clearly identified location as optional text with provenance, without geocoding or live venue verification.

Source information and user notes survive enrichment. No AI autosave or silent overwrite. A useful title is required at save time; optional metadata never becomes a mandatory form. Duplicate URL warnings are owner-scoped and non-blocking; similar titles never trigger automatic merging.

## Explicit non-goals

Native builds/share extensions, Android native sharing, browser extensions, platform imports, aggressive social scraping, video downloads/transcription, social networking/following, shared accounts or collections, collaborative planning, bookings, event discovery, navigation integration, complex itineraries, live weather, calendars, background AI agents, scheduled reminders, push, payments/subscriptions, feeds, advanced analytics, complex recommenders, dedicated vector databases, and multi-agent frameworks. No speculative infrastructure for these features.

## Error and fallback behavior

- URL inaccessible, blocked, unsupported, or timed out: preserve the entered URL, explain the limitation, allow manual title and save. Never bypass platform restrictions.
- AI refusal, invalid output, timeout, or quota exhaustion: retain draft/source and allow manual entry. AI failure never implies save failure.
- Invalid/oversized image: explain restrictions before retry; offer a manual idea. Failed storage upload cannot be reported as an image saved.
- Save/network failure: retain draft in current memory and offer explicit retry; prevent duplicate submissions. No false success state.
- Expired session: reauthenticate; never show cached data from another account. Clear private state on logout/account change.
- Empty/no suitable collection match: explain no matches and missing information; do not insert generic internet suggestions.
- Missing price/hours/availability: say unknown; do not equate absence with free/open/available. Old saved facts are not live verification.
- Broken original URL: keep the source record and saved content; communicate that the external page is unavailable.

## Proposed defaults requiring product acceptance

Fixed optional category keys (food, activity, travel, film-series, recipe, product, book, place, other), free-form tags, and reversible `saved` / `done` statuses. Null category means uncategorized. Session-only chat; no conversation recovery after reload. Invite-only email OTP recommended for the pilot. Online-only data operations; installation does not imply offline collection access.

These are recommendations, not additional confirmed requirements. Approve as one MVP behavior package before relevant tasks; change labels without coupling domain logic to the working product name.

## Success and lightweight validation

PoC release gate: all three inputs save; AI-off saving works; original sources reopen; edit/delete/search work; grounded follow-ups work; two-user isolation tests pass; physical iPhone Safari workflow succeeds.

Proposed usefulness experiment: owner saves 30 real ideas over two weeks, records save time for ten captures, collection reopenings, useful/not-useful responses on ten real requests, and whether a suggestion leads to an activity or decision. Aim for at least 8/10 relevant retrieval cases and median manual capture under 30 seconds; these are provisional evaluation targets, not established findings. Use a local tally and feedback notes, not analytics infrastructure. Small-collection usefulness and willingness to return are more important than hypothetical willingness to pay.

Open product choices: accept the defaults above; decide what qualifies as useful after the pilot. Commercial validation and persistent chat are deferred, not hidden MVP commitments.
