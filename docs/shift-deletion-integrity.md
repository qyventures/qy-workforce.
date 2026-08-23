# Shift deletion integrity

## Purpose

A shift is a root record for accepted assignments, attendance events, timesheets and downstream payroll evidence. The original schema allowed Ops users to manage shifts with a broad `FOR ALL` RLS policy, while `shift_assignments.shift_id` uses `ON DELETE CASCADE`. A physical shift deletion could therefore erase operational and financial history through cascading foreign keys.

## Control

Migration `202608232020_shift_deletion_integrity.sql` makes cancellation the supported business operation and prevents authenticated API users from physically deleting shifts.

The control has two layers:

1. `DELETE` is revoked from `authenticated` and `anon` on `public.shifts`.
2. A `BEFORE DELETE` trigger rejects deletion whenever a Supabase authenticated user context is present (`auth.uid()` is not null).

This preserves assignment, attendance, timesheet and payroll history and avoids bypassing audit/retention controls through a destructive parent-row delete.

Database/service maintenance without an authenticated end-user context remains possible for controlled migrations and break-glass administration.

## Operational behaviour

Ops should set `shifts.status = 'cancelled'` rather than delete a shift. Existing assignment cancellation, attendance integrity, timesheet and payroll controls continue to apply to the retained history.

## Regression coverage

`supabase/tests/shift_deletion_integrity_checks.sql` verifies that:

- `authenticated` and `anon` do not have shift DELETE privilege;
- the deletion guard trigger remains installed;
- the trigger function is `SECURITY DEFINER` with a pinned search path; and
- PUBLIC cannot execute the trigger function directly.
