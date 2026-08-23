# Payroll batch creation concurrency

## Risk

A sequential `NOT EXISTS` check is not sufficient to prevent duplicate active payroll membership when two finance users create overlapping batches concurrently. Under normal PostgreSQL isolation, both transactions can observe the same approved timesheet as unbatched before either transaction commits.

## Control

`create_payroll_batch(date,date)` now acquires a transaction-scoped PostgreSQL advisory lock for the short batch-construction critical section. Payroll batch creation is low-frequency, so serializing this path is an acceptable trade-off for financial integrity.

After the lock is acquired, the RPC:

1. creates the draft batch;
2. selects only `approved` timesheets in the requested pay period;
3. excludes any timesheet already belonging to a non-cancelled payroll batch;
4. writes batch items; and
5. records an audited batch-created event.

The lock is released automatically at transaction end. It does not serialize attendance, timesheet submission, supervisor review, or payroll export.

## Authorization

The RPC remains `SECURITY DEFINER` with `search_path=public`. Only application roles `finance` and `admin` may proceed. Anonymous callers have no execute permission.

## Validation

`supabase/tests/payroll_batch_creation_concurrency_checks.sql` statically verifies the advisory lock, approved-only selection, active-batch exclusion, SECURITY DEFINER/search-path hardening, and execution privileges. A clean staging database should also exercise two concurrent overlapping batch-creation calls before production promotion.
