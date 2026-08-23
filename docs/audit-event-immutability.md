# Audit event immutability

QY Workforce treats `audit_events` as append-only operational and compliance evidence.

## Control

Migration `202608231821_audit_event_immutability.sql` adds a database trigger that rejects every `UPDATE` and `DELETE` against `public.audit_events`. This applies even to privileged SQL paths. If an earlier event needs clarification, the application must append a new compensating event instead of rewriting history.

The migration also explicitly revokes `UPDATE`, `DELETE`, and `TRUNCATE` from `authenticated` and `anon`. Existing RLS remains in place as an additional boundary.

## Retention

Audit events remain a manual/legal-review retention class. The current automated retention job does not delete audit history. Any future audit-retention design must use a separately reviewed archival or cryptographic retention workflow rather than silently weakening this append-only control.

## Security rationale

Audit records are relied on by worker vetting, identity/residency/work-eligibility decisions, attendance, supervisor review, payroll, privacy requests, retention maintenance, and administrative changes. An immutable database boundary reduces the risk that an accidental privilege grant, broad RLS change, or compromised privileged workflow can erase the evidence trail.

## Test coverage

`supabase/tests/audit_event_immutability_checks.sql` verifies:

- the append-only trigger exists;
- the guard is `SECURITY DEFINER` with `search_path=public`;
- `authenticated` and `anon` lack direct mutation privileges; and
- direct privileged `UPDATE` and `DELETE` attempts fail.

No production credentials are required by this control or its tests.
