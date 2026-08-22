# Accepted shift terms integrity

Once a worker accepts a shift, the backend treats the worker-facing and commercial terms that informed that acceptance as immutable.

## Protected fields

For a shift with at least one active accepted assignment, direct updates may not change:

- site;
- role;
- start time;
- end time;
- worker hourly rate; or
- client hourly rate.

Headcount may still be increased for operational fulfilment, but it cannot be reduced below the number of active accepted assignments.

Cancelled assignments do not keep the freeze active by themselves. If no active accepted assignments remain, normal authorised shift-management rules apply again.

## Why this is enforced in Postgres

Timesheet amounts are derived from shift rates. A UI-only restriction would therefore be insufficient: an authorised or compromised client could otherwise mutate the stored rates after acceptance and change later payroll or margin calculations. The trigger in `202608230721_shift_terms_integrity.sql` enforces the invariant at the database boundary regardless of application path.

This control does not create a production pricing workflow, override RLS, or introduce external credentials. Any future exception/repricing workflow should be explicit, separately authorised and auditable rather than bypassing this trigger.

## Regression coverage

`supabase/tests/shift_terms_integrity_checks.sql` verifies that the trigger exists, is not directly executable by anon/authenticated roles, scopes the freeze to active accepted assignments, and retains all protected fields including accepted-capacity protection.
