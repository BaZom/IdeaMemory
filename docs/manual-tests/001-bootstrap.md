# Manual test — Task 001 bootstrap

Covers the checks automation cannot prove: real browser behavior, the explicit Retry flow and physical iPhone Safari ([T001-AC8](../plans/001-mvp.md#task-001--project-bootstrap)). Automated checks (`make check`) are a prerequisite, not a substitute.

**Since Task 002:** the app opens on the sign-in page; open the connection check with the network icon in the app bar, then follow the steps below. LAN builds also need `WEB_SUPABASE_URL` (see the [Task 002 manual test](002-auth.md)).

Use only synthetic, non-sensitive conditions. No credentials are needed. Record a result for every step; a skipped step is **Not run**, never **Pass**.

## Before you start

- [ ] `make setup` succeeded and `make check` exits 0 on the revision under test.
- [ ] Note the revision: `git rev-parse --short HEAD` (or “uncommitted working tree, <date>”).
- [ ] Ports 3000 and 8000 are free: `lsof -i :3000 -i :8000` prints nothing.

## Part A — Desktop browser (Chrome)

Start the API with `make run-api` (terminal 1) and the app with `make run-web` (terminal 2).

| # | Step | Expected result |
| --- | --- | --- |
| A1 | Wait for the app to open at http://localhost:3000 | Page title “Idea Memory”, app bar “Connection check”. A spinner with “Checking connection…” may flash briefly |
| A2 | Wait for the check to finish | Check icon, “Connected”, “The API is reachable.”, line “API: http://localhost:8000”. No Retry button |
| A3 | In DevTools → Network, reload | Exactly one `GET /health` request, status 200, response `{"status":"ok"}`. No further requests while idle (no polling) |
| A4 | Stop the API (Ctrl+C in terminal 1), then reload the page | “Connection failed”, “The API could not be reached.”, a **Retry** button |
| A5 | Wait 30 seconds without touching anything | Still failed; no new `/health` requests in Network (no automatic retry) |
| A6 | Press **Retry** while the API is still stopped | Spinner briefly, then failure again. Exactly one new `/health` request |
| A7 | Restart the API (`make run-api`), press **Retry** | “Connected”. Exactly one new `/health` request |
| A8 | Stop the API, reload, then click **Retry** rapidly several times | At most one `/health` request in flight at a time; the button disappears while checking |
| A9 | Restart the API with a different allowed origin: `make run-api ALLOWED_ORIGINS=http://localhost:3999`, then reload | “Connection failed” (the browser blocks the response). Console shows a CORS error. It must **not** show “Connected” |
| A10 | Restart the API normally (`make run-api`), press **Retry** | “Connected” |
| A11 | DevTools device toolbar: iPhone SE (375×667), then rotate to landscape; repeat with the API stopped | Text and Retry button fully visible, no overflow stripes, no horizontal scrolling |
| A12 | Tab to the Retry button (API stopped) and press Enter/Space | Visible focus on the button; pressing it retries |

Optional slow-API check: with the API stopped, run `python3 -c "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',8000)); s.listen(); time.sleep(60)"` (accepts connections but never answers), then reload. Expected: “The API did not respond in time.” after about 8 seconds. Stop it with Ctrl+C.

## Part B — Physical iPhone Safari (T001-AC8)

Requires an iPhone and Mac on the same **trusted** Wi-Fi network. Stop any servers from Part A first.

```sh
IP=$(ipconfig getifaddr en0)   # try en1 if empty
make run-api API_HOST=0.0.0.0 ALLOWED_ORIGINS=http://$IP:3000                    # terminal 1
make build-web API_BASE_URL=http://$IP:8000 && make serve-web WEB_HOST=0.0.0.0    # terminal 2
```

| # | Step | Expected result |
| --- | --- | --- |
| B1 | In Safari on the iPhone, open `http://<IP>:3000` | Page loads; “Connected”; line shows `API: http://<IP>:8000` (not localhost) |
| B2 | Stop the API (Ctrl+C in terminal 1), then pull down / reload in Safari | “Connection failed” with **Retry** |
| B3 | Restart the API with the same command, tap **Retry** | “Connected” |
| B4 | Rotate to landscape, then back to portrait, in both connected and failed states | Content stays centered and readable; Retry fully visible and tappable; no clipped text or sideways scrolling |
| B5 | Tap Retry with a thumb in portrait and landscape | Responds on first tap; target feels comfortably sized |
| B6 | Check the area near the notch / home indicator in both orientations | No content hidden under the status bar or home indicator |

Not in scope for this test (Task 008): HTTPS, Add to Home Screen, offline behavior, app updates. If the page does not load at all, check the Mac firewall, that both devices use the same network, and that `IP` is the Wi-Fi address.

When finished, stop both servers (Ctrl+C in each terminal).

## Results record

Copy this block into the PR description or review handoff.

```text
Task 001 manual test
Date:
Tester:
Revision:                      (commit or "uncommitted working tree")
Mac / Chrome version:
iPhone model:
iOS version / Safari:

Part A  A1:   A2:   A3:   A4:   A5:   A6:   A7:   A8:   A9:   A10:   A11:   A12:
Slow-API (optional):
Part B  B1:   B2:   B3:   B4:   B5:   B6:
        (Pass / Fail / Not run)

Failures and notes:
```

T001-AC8 is passed only when every Part B step passes on a physical iPhone and the record is filled in.

## User-reported result

After receiving the iPhone Safari instructions, the product owner reported: “it works.” This confirms a successful user-reported smoke test. Device model, iOS/Safari version, tested revision and individual step results were not supplied, so the detailed checklist above remains unfilled; this is not a claim that Codex observed or independently ran the device checks. Task 001's code-review findings and remote CI are separate verification items.
