# Worker Review Security Model

QY Workforce keeps worker readiness decisions server-authoritative. Ops/Admin users may review role interests, vetting outcomes and final operational status only through audited `SECURITY DEFINER` RPCs.

## Privacy boundary

`get_worker_review_queue()` returns only operational readiness fields and a pseudonymous worker alias derived from the worker UUID. It intentionally excludes display name, phone number, national identifiers, bank details and raw identity-provider payloads.

## Role review

`review_worker_role()` locks the worker-role row before changing approval state, requires Ops/Admin authority, blocks self-review, requires a reason for decline and writes an audit event. Role interest and role approval remain separate concepts.

## Vetting review

`review_worker_vetting()` accepts only `passed`, `failed` or `manual_review`. Failed/manual-review decisions require a redacted operational note. The RPC row-locks the vetting item, prevents self-review, records reviewer/time and writes an audit event. Raw documents should remain outside `notes_redacted`.

## Final operational status

`set_worker_operational_status()` is the explicit Ops gate for worker status. Setting `deployable` is refused unless the live deployment prerequisites are currently satisfied. Those prerequisites keep identity verification, residency verification and work eligibility separate and also enforce active role approval, vetting, training freshness and required consent.

Suspension and rejection require a reason and are audited. A stored `deployable` status is never sufficient on its own: shift discovery and acceptance still call the live deployability predicate.

## RPC-only mutations

Direct authenticated mutation privileges are revoked for `worker_profiles`, `worker_roles` and `worker_vetting`. Application clients should call the review RPCs instead. This prevents an Ops browser session from bypassing audit logging or server-side separation-of-duties checks through direct table writes.

## CI/staging invariants

`supabase/tests/worker_review_security_checks.sql` verifies that:

- review RPCs remain `SECURITY DEFINER`;
- direct authenticated worker-review writes remain disabled;
- role/vetting decisions lock target rows and prohibit self-review;
- adverse operational status decisions require a reason;
- deployable status requires live prerequisites;
- the review queue remains pseudonymous and does not introduce display-name/phone fields.

Production identity-provider credentials are not required for these controls and must not be added to migrations or test fixtures.
