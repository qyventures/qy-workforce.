# Backend security, identity and payroll boundaries

## Identity / Singpass / MyInfo

QY Workforce treats identity verification, residency and work eligibility as separate facts. A successful identity check must never imply residency or employment eligibility.

The database stores only normalized verification outcomes and hashes needed for correlation/audit. It must not store Singpass/MyInfo access tokens, refresh tokens, ID tokens, raw payloads or national identifiers in `identity_provider_sessions`.

`start_identity_session` supports only `mock` and `staging` environments. Production completion is intentionally disabled until production credentials, redirect URIs, privacy review and operational approval are in place.

Identity sessions are short-lived and single-active per worker/provider/environment. Starting a new flow expires stale sessions and rejects overlapping live sessions to reduce callback confusion and replay risk. State and nonce values must be supplied as sufficiently long hashes rather than raw secrets.

The identity-session table is also a forward-only state machine: only `initiated → callback_received|failed|expired` and `callback_received → completed|failed|expired` are valid. Its transport fields (worker, provider/environment, state/nonce hashes, scope contract and expiry) are immutable after creation. A completed session requires a bounded lowercase hexadecimal provider-subject hash and completion timestamp; failed and expired sessions cannot retain that hash. This protects the staging abstraction from accidental reopening or cross-session correlation changes.

The provider/environment pairing is fixed: `mock` is available only in the `mock` environment, and `singpass_myinfo` only through the `staging` abstraction. The database accepts only the fixed `openid` scope from worker clients; any provider-specific attribute scope must be configured and filtered in the protected staging bridge, never supplied by a mobile client. New rows are protected by both the RPC validation and forward-only database constraints; pre-existing invalid staging rows cannot be completed. API roles cannot select `identity_provider_sessions` directly, because those rows contain state/nonce and correlation hashes. Workers use `get_own_identity_session_status()` instead; it returns lifecycle status and timing only, never transport or subject hashes.

`mark_identity_callback_received_staging`, `fail_identity_session_staging` and `expire_identity_sessions` provide explicit, audited lifecycle transitions. The bulk expiry RPC is intended for service-role scheduling, while Ops/Admin can perform staging operational recovery. Production callback handling remains disabled.

`complete_identity_verification_staging` is an Ops/Admin boundary. Completion requires an unexpired session that has passed through the explicit callback-received state and a hashed provider subject. The retained legacy parameters for residency and work eligibility are rejected when populated, so identity completion cannot imply either outcome.

Residency and work eligibility use separate Ops/Admin boundaries: `record_residency_verification_staging` and the expiry-aware `record_work_eligibility_staging`. Residency verification requires an explicit category when passed. Work eligibility requires its own active worker consent, an independent reviewer, a bounded future expiry and an opaque evidence reference. Each review appends an immutable normalized history row and emits a distinct audit action; raw evidence and document identifiers do not belong in the database. None of the three outcomes automatically changes another.

## Worker readiness

Deployability remains server-authoritative. Worker clients may express role interests and submit consent, but cannot self-approve role, vetting, training, identity, residency, eligibility or deployability state. An `eligible` outcome is deployable only until `eligibility_expires_at`; legacy eligible rows without an expiry fail closed until independently re-reviewed. Training expiry, blocking vetting and consent withdrawal continue to take effect immediately through the same live predicate. `get_worker_readiness()` uses that exact predicate for its `deployable` flag, so its privacy-safe worker UI summary cannot claim readiness when matching or clock-in would fail.

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

Only Finance/Admin can create, lock or export payroll batches. Authenticated clients have no direct mutation privileges on payroll batches, items, adjustments or payouts; all changes use audited RPCs. Locking is serialized, rejects empty batches, revalidates that every item is still approved, prevents a timesheet from entering multiple locked/exported batches, and moves included timesheets to `payroll_ready`.

Export requires a locked batch with a prepared payout for every item and no pending adjustments. Finalization verifies a canonical SHA-256 checksum and checks the supplied row count against the database item count under a row lock. Recorded export evidence is immutable; an exact retry is idempotent, while a changed format, checksum or count is rejected. The older export finalizer without evidence is not callable by authenticated users. Payment-rail credentials and bank credentials remain outside this database.

Payroll adjustments require a second Finance/Admin reviewer and cannot be created or reviewed once a batch is exported. If a pending payout row already exists, an approved adjustment updates that pending amount under lock; once payout processing begins, adjustments fail closed. Payout rows can be prepared only before export. Moving a payout to `paid` requires a bounded external settlement/receipt reference, while audit metadata records only that a reference is present—not the reference itself. Cash exceptions additionally require a reason.

## Margin reporting

`get_site_margin_report(start,end)` is restricted to Ops Manager, Finance, Admin and Auditor. It aggregates worker cost, client revenue and gross margin by client/site without returning worker identity fields.

The older `site_margin_summary` view is no longer directly selectable by the authenticated role; privileged reporting should use the RPC so application-role authorization is enforced at the server boundary.

## Retention and privacy requests

Retention periods are registry-driven and intentionally reviewable before production. Identity verification storage is limited to normalized outcomes/evidence metadata; unnecessary raw identity data should not be retained.

Workers can submit `access`, `export` and `erasure` requests only through the audited `request_privacy_action(...)` RPC. Duplicate active requests of the same type are blocked. Workers may read their own request status through RLS, while only Admin/Auditor may read the operational queue.

`review_privacy_request(...)` is Admin-only, locks the request row before transition, prevents self-review, requires reasons for rejection/cancellation and records the decision in the audit trail. Erasure cannot be marked completed while a retention hold is active.

The V1 backend deliberately does not hard-delete payroll, attendance or audit records when an erasure request is submitted. Erasure is a controlled workflow requiring a retention/legal review first. A later production purge/anonymisation job should operate only on approved requests after any statutory, dispute, payroll and security retention obligations have expired.

## Staging validation

After migrations are applied to a staging Supabase project, run `supabase/tests/backend_security_checks.sql`, `supabase/tests/worker_review_security_checks.sql`, `supabase/tests/readiness_parity_and_identity_scope_checks.sql` and `supabase/tests/identity_session_lifecycle_integrity_checks.sql` in CI or psql. The checks assert RLS on identity sessions, demand tables and privacy requests; absence of raw token/national-ID columns; separation of identity/residency/eligibility fields; fixed minimum identity scopes; immutable identity-session transport fields and fail-closed lifecycle transitions; worker-readiness parity with the live deployment predicate; required SECURITY DEFINER boundaries; no direct authenticated mutation privileges for shifts/attendance/timesheets/payroll/privacy requests or worker qualifications; no broad margin-view access; single-active identity-session enforcement; required retention policies; concurrency/separation-of-duties controls on timesheet and worker-training review; declared-interest enforcement for role approval; serialized duplicate-safe payroll locking; immutable, count-bound export evidence; and locked, retention-aware privacy request review.
