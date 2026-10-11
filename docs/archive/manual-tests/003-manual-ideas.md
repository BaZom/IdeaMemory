# Manual test — Task 003 manual ideas

**Status: written 2026-10-11; not yet executed.**

Covers what automation cannot prove: saving, browsing, editing and deleting ideas in a real browser, long text with the on-screen keyboard, back navigation, reload and second-user isolation on desktop and on a physical iPhone ([T003-AC11](../plans/001-mvp.md#acceptance-criteria-and-evidence)). `make check` is a prerequisite, not a substitute.

Use throwaway accounts created in the app (e.g. `tester-a`, `tester-b`) and non-sensitive text. Record a result for every step; a skipped step is **Not run**, never **Pass**.

## Before you start

- [ ] `make check` exits 0 on the revision under test; note `git rev-parse --short HEAD` (or “uncommitted working tree, <date>”).
- [ ] `make supabase-start` succeeded (it also applies pending migrations). `make list-users` still shows accounts created before Task 003.
- [ ] Prepare a long text (≈ 2,000 characters with several paragraphs, indented lines and an emoji) to paste.

## Part A — Desktop browser (Chrome)

Run `make run-api` (terminal 1) and `make run-web` (terminal 2); open http://localhost:3000.

| # | Step | Expected result |
| --- | --- | --- |
| A1 | Sign in with an account that existed before Task 003 | Signs in; **Your ideas** with “No ideas yet” |
| A2 | Sign up tester A | **Your ideas** opens immediately, empty; no setup or email step |
| A3 | **New idea**, press **Save** with an empty title | “Enter a title.”; nothing saved (DevTools → Network: no POST) |
| A4 | Enter only a title; **Save** | Back on the collection with the idea at the top and “Idea saved” |
| A5 | **New idea**, type a title, press the browser back button | “Discard this draft?”; **Keep editing** keeps the text; back again → **Discard** saves nothing |
| A6 | **New idea** → **More details**: description, category, tags `Food, food, Night`, location, notes and the long text as *Original text*; **Save** | Saved; open it: tags `Food`, `Night`; original text shown exactly (spacing, line breaks, emoji) |
| A7 | DevTools → Network: inspect the POST | `Authorization: Bearer …`; `cache-control: no-store` in the response |
| A8 | Open an idea and its edit form | No done/status control anywhere (owner decision: ideas are not marked done) |
| A9 | Edit (pencil): change the title, clear the description and location; **Save** | Detail shows the new title; description/location gone; original text unchanged |
| A10 | Delete (bin) → **Cancel** | Nothing deleted |
| A11 | Delete (bin) → **Delete** | Back on the collection without it; after deleting the last one, “No ideas left” |
| A12 | Create 25 ideas (title only is fine), reload | Newest first, **Load more** shows the rest once each |
| A13 | Stop the API, try **Save** on a new idea | “Could not reach the server…”, draft kept; restart the API, **Save** again → saved |
| A14 | Stop the API, open the collection (reload) | “Your ideas could not be loaded…” with **Retry**; works after restarting |
| A15 | Account icon → **Sign out**; sign up tester B | B's collection is empty; none of A's ideas, titles or drafts appear anywhere |
| A16 | As B, paste one of A's idea URLs/IDs into a request (DevTools: `fetch` to `/api/v1/ideas/<A's id>` with B's token) | `404`; same body as an unknown ID |
| A17 | DevTools device toolbar: iPhone SE portrait and landscape on collection, form (details open) and detail with long text | Everything reachable; no overflow or horizontal scrolling |

## Part B — Physical iPhone Safari

Same trusted Wi-Fi; commands in [development: Physical iPhone check](../development.md#physical-iphone-check-lan-non-sensitive).

| # | Step | Expected result |
| --- | --- | --- |
| B1 | Sign up a new account on the phone; save a title-only idea | Saved and listed |
| B2 | New idea with **More details**; paste the long text into *Original text*; scroll with the keyboard open | Every field reachable above the keyboard; **Save** reachable |
| B3 | Open the idea; edit, back with the Safari/edge-swipe back gesture | Returns to the previous page; an edited, unsaved form asks before discarding |
| B4 | Close the tab and reopen the URL | Session and ideas restored |
| B5 | Rotate to landscape and back on all three pages | Nothing hidden under the notch or home indicator |
| B6 | Delete an idea; sign out; sign in as tester A | Phone account's ideas not shown to A, and vice versa |

When finished: stop the API and web servers, then `make supabase-stop`.

## Results record

```text
Task 003 manual test
Date:
Revision:
Desktop browser/version:
iPhone model / iOS version:
A1–A17: (Pass/Fail/Not run, notes per step)
B1–B6:  (Pass/Fail/Not run, notes per step)
Issues found:
```
