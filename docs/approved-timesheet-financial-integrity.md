# Approved timesheet financial integrity

Supervisor/ops approval is the financial control point for a QY Workforce timesheet. After approval, the attendance-derived financial basis must remain stable through payroll batching, payroll export and client/site margin reporting.

Migration `202608230821_approved_timesheet_financial_integrity.sql` adds a database trigger that rejects updates to these fields when the existing timesheet status is `approved` or `payroll_ready`:

- `assignment_id`
- `payable_minutes`
- `worker_amount`
- `client_amount`

The guard deliberately does **not** block the normal `approved -> payroll_ready` status transition used by payroll locking, provided the financial basis is unchanged.

This is defense in depth. Authenticated clients are already routed through controlled RPCs and RLS, but a database invariant prevents a privileged application bug, migration or ordinary SQL update from silently changing a supervisor-approved payroll amount.

If a genuine correction is required after approval, do not mutate the approved record in place. Use an explicit audited correction workflow/migration so the original approval evidence and the reason for the adjustment remain reconstructable.

Regression coverage lives in `supabase/tests/approved_timesheet_financial_integrity_checks.sql` and verifies that the trigger exists, remains invoker-security, and continues to protect the full payroll/margin basis.
