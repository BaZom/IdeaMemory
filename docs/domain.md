# Domain model

Status: proposed schema, constrained by confirmed R1–R6 in [product](product.md). No migrations exist.

## Concepts and relationships

| Concept | Proposed representation | Rules |
| --- | --- | --- |
| User | Supabase Auth identity | Auth UUID owns all private resources; no duplicate password/profile table without need |
| Idea | `ideas` | UUID, owner UUID, nonblank title, optional description/category/notes/location text, tags array, status, UTC created/updated timestamps, version |
| Source | `sources` | UUID, owner, idea UUID, kind (`url`, `image`, `text`), immutable original URL/text or private object reference, bounded metadata JSON, extraction provenance/time |
| Upload | `uploads` resource bookkeeping | UUID, owner, opaque object key, validated MIME/size, state, created/expiry times; needed for abandoned uploads and reliable cleanup |
| Category | Nullable stable string key with DB validation | Fixed list initially; no category entity, CRUD, or hybrid taxonomy |
| Tag | Normalized text array on idea | Deduplicate case-insensitively, trim, bound count/length; no separate tag entity without tag-management requirements |
| Processing result | Transient response | Suggested fields, warnings, provenance; not a durable job/entity |
| Conversation | Bounded client memory | Active-session turns and referenced IDs; no chat tables or provider thread dependency |

User 1 → many Ideas; Idea 1 → zero/many Sources; User 1 → many Uploads; image Source → exactly one ready owned Upload. Initially no upload sharing across sources/ideas, simplifying deletion. Source belongs to exactly one idea. Upload bookkeeping is storage consistency, not an AI processing queue.

## Integrity and ownership

- Every row/resource has an owner derived from verified identity, never trusted from request JSON. Owner cannot change.
- Composite foreign keys `(idea_id, owner_id)` and `(upload_id, owner_id)` prevent cross-owner attachment, with corresponding unique referenced pairs. Source kind constraints enforce required payloads. Upload attachment is unique.
- Idea can exist with zero sources or null category. Removing its last source leaves the idea intact.
- Source metadata is evidence, not canonical user content. Preserve original URL including meaningful query parameters; keep normalized comparison URL separately. Do not rewrite the original on enrichment.
- Save idea and sources in one database transaction; server validates uploaded references. Client retries carry a bounded owner-scoped operation key so network retries return the previous result, not another idea. Retain deduplication records only for a documented retry window.
- Version-checked edits return a conflict rather than silently overwriting another tab's changes. No full revision-history system proposed.
- Model suggestions and extraction metadata carry origin/time; accepted idea fields are editable canonical values. Retain the proposed extraction snapshot in bounded source metadata only when saved; do not store full prompts/responses. Manual source text remains separate where provided.
- Location is nullable user-confirmed text; no inferred coordinates or required geography. No invented price or availability fields.

## Lifecycle

Draft stays in client memory; processing returns suggestions; user confirms a transaction that creates the idea. Processing failure returns to editable draft. Retry/cancel never silently saves. Existing idea enrichment is an explicit review-and-apply operation, not background mutation.

Idea transitions `saved ↔ done` are user-controlled; proposed recommendation default includes saved items, with explicit query support for done items. Deletion hides the idea immediately from all reads/retrieval and marks linked uploads for cleanup. After cleanup, hard-delete content and source rows; do not retain private content as an audit trail. Database rows needed to retry object deletion contain only owner, object key, and deletion state.

Upload transitions: `pending → ready → attached`; abandoned pending/ready uploads expire after proposed 24 hours; `attached → deleting → removed`. Create bookkeeping before object upload; failed upload is recoverable/expirable. Recheck state in the attachment transaction to prevent cleanup racing a save. Mark deletion before removing an object; retry safely if Storage or final database update fails. This is not a distributed transaction.

Task 005 provides an idempotent operator-invoked reconciliation command for pending/expired/deleting resources and storage orphans; run daily during the pilot and verify results. No queue or scheduler is required. Cleanup also runs on explicit cancellation/deletion where feasible. Document any delayed erasure rather than reporting full deletion prematurely.

Account deletion, initially a documented authenticated operator-assisted procedure, removes ideas, sources, objects and identity; verify completion including cleanup failures. Restore procedures must reapply deletion records so a backup does not resurrect erased content. Proposed backup retention must be disclosed.

## Duplicates, history, portability

Normalize URL scheme/host casing, default port and fragment for comparisons; preserve path/query semantics and signed URLs. Warn on matching normalized URLs within the same account. User may save separately; no global lookup or uniqueness rejection that reveals another user. No title similarity merging.

Historical requirement is original source preservation plus timestamps/provenance, not event sourcing or unlimited edit history. SQL exports, JSON idea/source records, and original image files should form an operator-generated portable export with a manifest mapping object keys. A self-service export UI is deferred.

## Approval points

Category/status and conversation defaults affect behavior; upload retention/deletion affect privacy; API/database ownership enforcement affects security. Approve the packages in [architecture](architecture.md) before implementation. Required privacy and source preservation are already confirmed; these proposed mechanics are not.
