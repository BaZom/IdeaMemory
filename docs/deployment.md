# CI/CD and deployment proposal

Status: no infrastructure, workflows, accounts or deploys created. Final hosting and spend require human approval.

## Hosting evaluation (official sources checked 2026-10-11)

| Component/options | Cost and compatibility | Recommendation |
| --- | --- | --- |
| Cloudflare Pages | Static build artifacts fit Flutter Web; Git/CI integration available; verify current build/asset/transfer limits | Preferred frontend: build pinned Flutter in CI and upload the verified artifact |
| Firebase Hosting | Static hosting with no-cost quotas and usage-based options; another project/CLI is needed beside Supabase | Good alternative if owner already operates Firebase |
| Render | Python web services; free instances sleep after inactivity, so cold starts distort mobile latency testing | Prefer a small paid instance for invited pilot; verify regional availability and actual quote |
| Railway | Python service deployment with base-plan and resource-usage charges | Alternative if owner prefers usage pricing; set alerts and verify available spending controls |
| Supabase | Managed PostgreSQL/Auth/private Storage; usage, egress and backup capabilities affect plan choice | Retain requested platform, verify EU region and backup/restore plan before provisioning |

This is an engineering recommendation, not a claim of cheapest total cost. Monthly forecast = frontend/egress + API compute + Supabase/database/storage/egress/backups + AI input/output/image usage + email delivery/domain if needed. Owner must approve a monetary ceiling; validate current account-specific quotes and quotas at provisioning rather than freezing prices in architecture. Free hosting does not imply zero-cost operation or production reliability.

Sources: [Cloudflare static deployment](https://developers.cloudflare.com/pages/framework-guides/deploy-anything/), [Firebase pricing](https://firebase.google.com/pricing), [Render free-service limits](https://render.com/docs/free), [Railway pricing](https://railway.com/pricing), [Supabase pricing](https://supabase.com/pricing). The Supabase pricing link is a recheck reference, not a verified plan quote.

## CI proposal

Task 001 introduces GitHub Actions for pull requests and main-branch verification, pinned toolchains, dependency caches keyed to lockfiles, least-privilege permissions and bounded job timeouts. Run Flutter format/analyze/tests/web build and Python Ruff/types/tests/package build. Task 002 adds a disposable local Supabase integration job for migrations, RLS/RPC/storage; no production credentials in tests. A fresh install of the built backend package catches packaging/import failures.

Test both migration-from-empty and upgrade from last schema when data changes. Add dependency vulnerability checks supported by the chosen ecosystems and a maintained secret scan; use scheduled or manual audits where practical, with actionable triage rather than unsupported claims that all Dart packages have an equivalent audit command. Required CI checks must not silently skip on path filters. Fork PRs receive no secrets and cannot deploy. CI provider calls are mocked; live AI quality checks are explicitly budgeted evaluations.

Human creates/configures GitHub remote and branch protection when ready. The deployment workflow is separate, manually triggered against a passed, reviewed commit/artifact with protected-environment approval where available. If the GitHub plan cannot enforce reviewers, keep the manual operator gate and document the limitation. Disable provider auto-production deploys on merge. Preview deployments, if authorized later, use synthetic/nonproduction data and restricted auth redirects, never production secrets.

## Environments and secrets

Local Supabase for development, then a separately approved hosted pilot environment; no mandatory staging fleet. Before public use, decide whether a separate staging project is justified. Choose suitable regions and review processor arrangements; an EU database does not guarantee that every downstream processor keeps all data in the EU.

Store OpenAI and operator Supabase secrets only server/operator side. Use distinct local/hosted values; rotate exposed keys. Public frontend settings include only API URL, Supabase URL and publishable key. Pin CORS origins and Auth redirect allowlists; require HTTPS. Storage remains private. Configure request size/time limits, quotas, health checks and logs that exclude private content. Operator cleanup credentials are not part of normal frontend/backend user configuration.

## Human-controlled release procedure

1. Review exact commit, required CI, migration change and unresolved risks; obtain release authorization.
2. Verify configured region, current cost ceiling, secrets, policies, private bucket and Auth invitation settings. Take an appropriate database backup and object export before risky data changes.
3. Apply backward-compatible additive migrations first, explicitly to the approved environment; verify grants/RLS. Use expand/migrate/contract if compatibility requires it; destructive contraction is a separately approved step.
4. Deploy the backend artifact compatible with both old and new frontend clients. Smoke-test health, auth, isolation and manual CRUD with synthetic accounts.
5. Publish the verified Flutter artifact. Validate headers, routing, auth redirect, manifest and physical iPhone Safari workflow.
6. Test URL/image/AI failure fallback, private source access, quotas, cleanup and deletion; record release commit and results. Do not report success until observed.

Production deployment, merges and releases stay human-controlled even if all checks pass.

## Rollback, backup and operations

Keep prior API/frontend artifacts. Roll back application artifacts only if compatible with the current schema. Prefer a reviewed forward migration; do not blindly run down migrations that lose user data. Restore tests need both PostgreSQL records and original Storage objects: do not assume database backups contain uploaded files. Document backup cadence, retention and restore time objective before real collection dependence; proposed pilot baseline is daily exports with seven-day retention, encrypted access-controlled copies, and a tested restore before invitations. Confirm costs and privacy disclosure first.

Run upload/deletion reconciliation daily as an operator action, checking failures; no scheduler service required initially. Record aggregate failure rates, latency, storage size and AI usage. Alert operator on repeated cleanup failures or spend thresholds; no user analytics platform. Incident response: disable affected capability, preserve minimal diagnostic evidence, rotate credentials if needed, investigate ownership exposure and assess notification duties as applicable. Before inviting users, test account deletion/export and ensure backups do not reintroduce erased data.
