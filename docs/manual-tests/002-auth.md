# Manual test — Task 002 authentication

**Status: rewritten 2026-10-11 for username + password accounts (owner decision); not yet executed.**

Covers what automation cannot prove: real browser sign-up and sign-in with a username and password, session restore after reload, sign-out and switching users on desktop and on a physical iPhone ([T002-AC10](../plans/001-mvp.md#task-002--authentication-and-private-access)). `make check` (including `check-integration`) is a prerequisite, not a substitute.

Use throwaway usernames (e.g. `tester-a`). No email address is involved. Record a result for every step; a skipped step is **Not run**, never **Pass**.

## Before you start

- [ ] `make check` exits 0 on the revision under test; note `git rev-parse --short HEAD` (or “uncommitted working tree, <date>”).
- [ ] Docker is running and `make supabase-start` succeeded.
- [ ] Pick three unused usernames: tester A, tester B and one for the iPhone. Create them in the app; do not use `make provision-user`.

## Part A — Desktop browser (Chrome)

Run `make run-api` (terminal 1) and `make run-web` (terminal 2); open http://localhost:3000.

| # | Step | Expected result |
| --- | --- | --- |
| A1 | Load the app | “Restoring your session…” briefly, then **Sign in** with a Sign in / Sign up switch, Username and Password fields; password hidden |
| A2 | Sign in with `a b` (with a space) and any password | “Use letters, numbers, dots, dashes or underscores, starting with a letter or number.” |
| A3 | Choose **Sign up**, enter tester A's username and the password `short` | “Choose a password with at least 8 characters.”; no account created (`make list-users`) |
| A4 | Sign up tester A with an 8+ character password; press **Create account** | Account page immediately: “Signed in”, tester A's username (no email shown anywhere), “Verified by the API”, a user ID matching `make list-users` |
| A5 | DevTools → Network: inspect the `/api/v1/me` request | `Authorization: Bearer …` header; `{"user_id": …}` with `cache-control: no-store`; no token or password in any URL |
| A6 | Reload the page | Restoring, then the account page again without signing in |
| A7 | **Sign out** | Sign-in page immediately; reload stays signed out |
| A8 | Sign in as tester A with a wrong password | “Username or password is incorrect.” |
| A9 | Sign in with a username that has no account | The same “Username or password is incorrect.” |
| A10 | Sign in as tester A (try typing it in capitals) with the correct password | Account page with the **same** user ID as A4 |
| A11 | Sign out; **Sign up** again with tester A's username and a different password | “That username is taken. Choose another, or sign in.” Then signing in with the new password fails and with the original password works |
| A12 | Sign up tester B; check the account page | B's username and a different user ID; nothing from A |
| A13 | While signed in, stop the API (Ctrl+C terminal 1) and reload | Still signed in; “The API could not be reached. You are still signed in.” with **Retry**. Restart `make run-api`, **Retry** → verified |
| A14 | Network icon in the app bar | Connection check opens and shows “Connected” |
| A15 | Press **Sign in** / **Create account** twice quickly | Only one request (DevTools → Network); button shows progress while busy |
| A16 | Eye icon in the password field | Shows and hides the password |
| A17 | DevTools device toolbar: iPhone SE portrait and landscape, on sign-in and account pages | All text, fields and buttons visible; no overflow or horizontal scrolling |

## Part B — Physical iPhone Safari

Same trusted Wi-Fi for Mac and iPhone. Stop servers from Part A first. Commands are in [development: Physical iPhone check](../development.md#physical-iphone-check-lan-non-sensitive) (note `WEB_SUPABASE_URL`).

| # | Step | Expected result |
| --- | --- | --- |
| B1 | Open `http://<IP>:3000` | Sign-in page with the Sign in / Sign up switch |
| B2 | **Sign up** with the iPhone test username (no autocorrect or auto-capitalisation; Safari may offer a strong password) | Account page with a new verified user ID |
| B3 | Close the tab and reopen the URL | Session restored without signing in |
| B4 | Rotate to landscape and back on sign-in and account pages, keyboard open and closed | Fields and buttons reachable; nothing hidden under the notch or home indicator |
| B5 | **Sign out**, sign in again with the same password, then sign out and sign in as tester B | The phone account keeps its ID; switching shows B only |
| B6 | Stop the API on the Mac, reload on the phone; restart it, **Retry** | Unavailable message while stopped; verified after retry |

Not in scope (later tasks): HTTPS, Add to Home Screen, app updates, account recovery and verification.

When finished: stop the API and web servers, then `make supabase-stop` (the stack's ports are reachable on your network while it runs).

## Results record

```text
Task 002 manual test
Date:
Tester:
Revision:                      (commit or "uncommitted working tree")
Mac / Chrome version:
iPhone model / iOS / Safari:

Part A  A1:  A2:  A3:  A4:  A5:  A6:  A7:  A8:  A9:  A10:  A11:  A12:  A13:  A14:  A15:  A16:  A17:
Part B  B1:  B2:  B3:  B4:  B5:  B6:
        (Pass / Fail / Not run)

Failures and notes:
```

T002-AC10 is passed only when Parts A and B pass with the record filled in.
