# Backend security, identity and payroll boundaries

## Identity / Singpass / MyInfo

QY Workforce treats identity verification, residency and work eligibility as separate facts. A successful identity check must never imply residency or employment eligibility.

Worker-profile constraints keep these facts internally consistent without merging them: identity verification requires its own timestamp, residency categories require verified residency, and resetting work eligibility to `unknown` clears stale eligibility evidence.

The database stores only normalized verification outcomes and hashes needed for correlation/audit. It must not store Singpass/MyInfo access tokens, refresh tokens, ID tokens, raw payloads or national identifiers in `identity_provider_sessions`.

`start_identity_session` supports only `mock` and `staging` environments. Production completion is intentionally disabled until production credentials, redirect URIs, privacy review and operational approval are in place.

Identity sessions are short-lived and single-active per worker/provider/environment. Starting a new flow expires stale sessions and rejects overlapping live sessions to reduce callback confusion and replay risk. State and nonce values must be supplied as sufficiently long hashes rather than raw secrets. The mock/staging contract permits only the `openid` correlation scope; it must not be expanded to retrieve raw MyInfo attributes without a separately reviewed provider contract.

`mark_identity_callback_received_staging`, `fail_identity_session_staging` and `expire_identity_sessions` provide explicit, audited lifecycle transitions. The bulk expiry RPC is intended for service-role scheduling, while Ops/Admin can perform staging operational recovery. Production callback handling remains disabled.

`complete_identity_verification_staging` is an Ops/Admin boundary. It can complete only an unexpired session that has first entered the audited callback-received state, requires an opaque provider-subject hash, and records identity outcome independently from residency and work eligibility. A residency category cannot be recorded unless residency is verified. It writes an audit event.

## Worker readiness

Deployability remains server-authoritative. Worker clients may express role interests and submit consent, but cannot self-approve role, vetting, training, identity, residency, eligibility or deployability state.

Operational consent is an append-only decision history. `worker_has_active_consent(...)` uses only the latest decision for each purpose, so a withdrawal immediately takes effect and an old grant cannot keep a worker deployable or start an identity session. Direct consent writes are denied; workers use `set_worker_operational_consent(...)`, which validates the purpose and policy version and emits a minimised audit event. The worker shift feed checks both live prerequisites and the separate Ops-managed `status='deployable'` gate; it must not advertise shifts that acceptance will reject.

## Shift demand lifecycle

Demand creation is server-authoritative. `clients`, `sites`, `roles` and `shifts` have RLS enabled, and anonymous/authenticated clients have no direct INSERT/UPDATE/DELETE privileges on those tables.

`create_shift_draft(...)` is restricted to Ops Manager/Admin and validates active client/site/role state, timing, headcount and rate safety bounds before creating a shift in `draft` status. The audit event records operational metadata and a low-margin flag without worker PII.

Publishing is deliberately separate. `open_shift(shift_id)` can transition only a future `draft` shift to `open`, revalidates client/site/role activity under a row lock, and writes an audit event. Workers never publish demand directly; they discover eligible open shifts through the scoped worker feed and accept through the capacity-safe acceptance RPC.

The current 10% margin threshold is an operational warning, not a database hard-stop. This avoids silently changing commercial policy while still surfacing low-margin demand for Ops review.

## Attendance and timesheets

Clock events are tied to an accepted assignment and validated server-side against the authoritative site geofence and timing window. Clock-out creates/updates a draft timesheet. Supervisor/Ops review is site-scoped and produces auditable approve/reject transitions.

Authenticated clients no longer have direct INSERT/UPDATE/DELETE privileges on `time_events` or `timesheets`; attendance and timesheet state changes must use the audited server RPCs. This prevents a modified client from fabricating geofence outcomes, payable minutes or approval/payroll state through direct table writes.

`review_timesheet(...)` locks the submitted timesheet before authorization and transition. This prevents two concurrent reviewers from both producing valid decisions or duplicate audit trails. Review also enforces separation of duties: a user who is the worker on the timesheet cannot approve or reject that same timesheet, even if they also hold a supervisor/Ops/Admin role.

## Payroll

Only Finance/Admin can create, lock or export payroll batches. A batch contains approved timesheets only. Locking a batch moves its included timesheets to `payroll_ready`. Export requires a locked batch and records format/count/checksum in the audit trail. Payment-rail credentials and bank credentials remain outside this database.

## Margin reporting

`get_site_margin_report(start,end)` is restricted to Ops Manager, Finance, Admin and Auditor. It aggregates worker cost, client revenue and gross margin by client/site without returning worker identity fields.

The older `site_margin_summary` view is no longer directly selectable by the authenticated role; privileged reporting should use the RPC so application-role authorization is enforced at the server boundary.

## Retention and privacy requests

Retention periods are registry-driven and intentionally reviewable before production. Identity verification storage is limited to normalized outcomes/evidence metadata; unnecessary raw identity data should not be retained.

Workers can submit `access`, `export` and `erasure` requests only through the audited `request_privacy_action(...)` RPC. Duplicate active requests of the same type are blocked. Workers may read their own request status through RLS, while only Admin/Auditor may read the operational queue.

`review_privacy_request(...)` is Admin-only, locks the request row before transition, prevents self-review, requires reasons for rejection/cancellation and records the decision in the audit trail. Erasure cannot be marked completed while a retention hold is active.

The V1 backend deliberately does not hard-delete payroll, attendance or audit records when an erasure request is submitted. Erasure is a controlled workflow requiring a retention/legal review first. A later production purge/anonymisation job should operate only on approved requests after any statutory, dispute, payroll and security retention obligations have expired.

## Staging validation

After migrations are applied to a staging Supabase project, run `scripts/release/run-supabase-checks.sh` with a staging-only connection value. The checks assert RLS on identity sessions, consent history, demand tables and privacy requests; absence of raw token/national-ID columns; separation of identity/residency/eligibility fields; required SECURITY DEFINER boundaries; latest-decision consent enforcement; no direct authenticated mutation privileges for shifts/attendance/timesheets/privacy requests; no broad margin-view access; single-active identity-session enforcement; required retention policies; concurrency/separation-of-duties controls on timesheet review; and locked, retention-aware privacy request review.
