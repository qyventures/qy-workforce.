# Payroll integrity controls

QY Workforce payroll is designed as an audited state machine rather than a set of directly editable tables.

## State flow

`approved timesheet -> draft payroll batch -> locked batch / payroll_ready timesheet -> exported batch`

Only Admin and Finance roles may invoke the payroll mutation RPCs. Authenticated clients do not receive direct INSERT/UPDATE/DELETE privileges on `payroll_batches` or `payroll_batch_items`.

## Batch creation

`create_payroll_batch(start, end)` selects only approved timesheets in the requested period. A timesheet already present in any non-cancelled payroll workflow is excluded, including another draft batch. Pay periods are bounded to 62 days to reduce accidental oversized runs.

## Locking

`lock_payroll_batch(batch_id)` locks the batch row and all member timesheets before transition. Empty batches are rejected. Every member must still be `approved`; otherwise the whole lock fails. Successful locking marks each member `payroll_ready` and records the lock actor and timestamp.

Payroll batch membership becomes immutable after the batch leaves `draft`. This is enforced by a database trigger in addition to client privilege revocation.

## Export evidence

`record_payroll_export(...)` requires a SHA-256 checksum and verifies that the caller-provided record count exactly matches the locked batch item count. Once export evidence is recorded, format, checksum and count are immutable. A repeated call is accepted only when it is identical, making retries idempotent without allowing evidence replacement.

The export actor, timestamp, format, count and SHA-256 checksum are recorded in the batch/audit trail. The checksum is evidence for the generated export file; the database does not store the export file itself.

## Cancellation

Only draft batches may be cancelled, and a reason is mandatory. Locked/exported batches cannot be cancelled through the normal application RPC because they form part of the payroll evidence chain.

## Security / staging validation

Run `supabase/tests/payroll_integrity_checks.sql` after migrations in staging. It asserts:

- RPC-only payroll mutations
- membership immutability trigger
- SECURITY DEFINER boundaries
- duplicate-active-batch prevention
- row-lock/state validation on payroll lock
- SHA-256/count reconciliation and immutable export evidence
- actor attribution for lock/export

Production payroll-bank/payment-provider integration remains outside this control plane. No bank credentials or production payout action is required for these controls.
