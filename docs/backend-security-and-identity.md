# Backend security, identity and payroll boundaries

## Identity / Singpass / MyInfo

QY Workforce treats identity verification, residency and work eligibility as separate facts. A successful identity check must never imply residency or employment eligibility.

The database stores only normalized verification outcomes and hashes needed for correlation/audit. It must not store Singpass/MyInfo access tokens, refresh tokens, ID tokens, raw payloads or national identifiers in `identity_provider_sessions`.

`start_identity_session` supports only `mock` and `staging` environments. Production completion is intentionally disabled until production credentials, redirect URIs, privacy review and operational approval are in place.

`complete_identity_verification_staging` is an Ops/Admin boundary. It records the identity outcome independently from residency and work eligibility and writes an audit event.

## Worker readiness

Deployability remains server-authoritative. Worker clients may express role interests and submit consent, but cannot self-approve role, vetting, training, identity, residency, eligibility or deployability state.

## Attendance and timesheets

Clock events are tied to an accepted assignment and validated server-side against the authoritative site geofence and timing window. Clock-out creates/updates a draft timesheet. Supervisor/Ops review is site-scoped and produces auditable approve/reject transitions.

## Payroll

Only Finance/Admin can create, lock or export payroll batches. A batch contains approved timesheets only. Locking a batch moves its included timesheets to `payroll_ready`. Export requires a locked batch and records format/count/checksum in the audit trail. Payment-rail credentials and bank credentials remain outside this database.

## Margin reporting

`get_site_margin_report(start,end)` is restricted to Ops Manager, Finance, Admin and Auditor. It aggregates worker cost, client revenue and gross margin by client/site without returning worker identity fields.

## Retention

Retention periods are registry-driven and intentionally reviewable before production. Identity verification storage is limited to normalized outcomes/evidence metadata; unnecessary raw identity data should not be retained.

## Staging validation

After migrations are applied to a staging Supabase project, run `supabase/tests/backend_security_checks.sql` in CI or psql. The checks assert RLS on identity sessions, absence of raw token/national-ID columns, separation of identity/residency/eligibility fields, required SECURITY DEFINER boundaries and the identity retention policy.
