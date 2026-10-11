# Risk register

Status: proposed mitigations. “Before PoC” means before that capability processes real data; some controls are needed as early as the first implementation slice. Deferral never permits another user's data to become accessible.

| Risk | Likely impact | Practical mitigation | Before PoC / deferral |
| --- | --- | --- | --- |
| Capture friction / inconsistent saving | Collection never becomes useful | Minimal required fields; manual fallback; observe save times and real owner use | Validate in pilot; defer automation/import features |
| Small collection / weak recommendations / low return rate | Product lacks repeat value | Seed with real ideas, evaluate relevance and return use; show honest empty state | Pilot experiment; no monetization infrastructure |
| Existing substitutes / willingness to pay | Commercial demand uncertain | Compare user habits and qualitative feedback after personal value is demonstrated | Business research can wait; no billing |
| Restricted social content / unreliable metadata | Empty or misleading drafts | Preserve URL; bounded metadata attempt; editable fallback; no aggressive scraping | Required Task 004 |
| Screenshot extraction errors | Wrong facts become trusted | Original image available, explicit review, provenance, representative samples | Required Task 005; advanced OCR pipeline deferred |
| Hallucinations / stale facts | Bad real-world decisions | Candidate/evidence validation, canonical facts, unknown/stale labels; no live availability claims | Required Task 007 |
| Cross-user exposure / direct-provider bypass | Private notes/images leak | Verified tokens, owner scoping, RLS/grants/constraints, private bucket; two-user API/Data API/Storage tests | Required from Task 002, never defer |
| Prompt injection in sources/history | Wrong instructions/data disclosure | Treat content as data, no tools/writes, bounded context, current-owner retrieval, adversarial tests | Required when AI added |
| URL SSRF / redirects / DNS rebinding | Internal service access | Scheme/address/port checks, validate every hop, safe connection binding and deadlines | Required Task 004; unsafe extraction disabled |
| Hostile or oversized images | Resource exhaustion | Decode/signature/type/byte/pixel limits, bounded concurrency and private storage | Required Task 005 |
| AI abuse / storage growth / repeated requests | Unexpected spend/outage | Atomic quota reservations, caps/timeouts, explicit retry, operator usage review | Before live AI/storage; billing features deferred |
| Provider/auth/storage outage | Interrupted capture / partial deletion | Draft retention, honest fallback, fail-closed auth, retriable storage cleanup | Each capability before pilot |
| Storage/DB inconsistency / abandoned uploads | Orphaned private data or broken sources | Upload ledger, checked attach transition, idempotent operator reconciliation | Task 005; distributed job infrastructure deferred |
| Loss of data / unsafe migrations | Irrecoverable collection loss | Migration tests, backups of DB plus objects, tested restore, human destructive gate | Before reliance/invitations; elaborate HA deferred |
| Safari/PWA incompatibility | Core experience unusable | Early physical device check, uploads/keyboard/back/install/update tests | Basic check Task 001, full release gate Task 008 |
| Web-to-native assumptions | Later rewrite cost | Isolate actual platform edges; avoid web-only domain APIs | Throughout; native builds deferred |
| Browser token exposure | Account compromise through XSS | Restrict scripts, escaped text, CSP, no unsafe imported HTML, logout state cleanup | Before authenticated pilot |
| Username-only accounts (accepted for MVP) | Forgotten password cannot be recovered except by operator reset; no verified contact for users; guessable passwords | Owner accepted 2026-10-11 to prioritise functionality; minimum 8-character passwords and provider rate limits remain; data isolation unchanged | Revisit before inviting real users (Task 008): recovery, verification, contact channel |
| Signed URL leakage / cache persistence | Temporary private-image disclosure | Short expiry, no logging, private response cache control; remove objects on deletion | Before screenshot pilot |
| Unclear retention/processor disclosures | Users misled about private content | Define retention and recipients, minimize AI inputs, document deletion and provider limits | Before anyone else's real data |

## Privacy stages and practical controls

Personal PoC: private storage and authorization still apply. Avoid third-party personal details in test screenshots where possible; use synthetic fixtures. Explain what goes to AI, allow manual entry without AI, and never claim zero retention without verified account controls. The proposed 24-hour abandoned-upload expiry, session-only chat, seven-day backups and immediate logical deletion must be documented and tested, including delayed physical cleanup. Saved originals remain until the user deletes them; a resized derivative does not replace the original.

Before invited users: evaluate the actual processing context and applicable GDPR duties rather than assuming a small/private pilot is exempt. Identify controller/processor roles, purposes and lawful basis, data minimization, processor contracts, international transfers, retention, access/export/deletion procedures and incident handling. Provide understandable privacy information before sending personal content to processors. Region selection alone is insufficient. A documented operator-assisted access/export/account-deletion process is proportionate; a full compliance administration UI is unnecessary.

Before public availability in Germany/EU: obtain a context-specific privacy/legal review, confirm disclosures and rights handling, vendor arrangements and security measures, evaluate whether additional assessments are required, and ensure production backup/deletion procedures match promises. Do not prescribe consent as the universal legal basis or claim compliance from this document.

The [European Commission's business/organisation data-protection guidance](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations_en) is the authoritative starting point for assessing obligations. These are implementation gates and open assessments, not a legal determination. Product telemetry stays a manual, content-minimized pilot tally unless a new requirement justifies more.
