#!/usr/bin/env bash
set -euo pipefail

TIMESHEET_MIGRATION="supabase/migrations/202608231147_timesheet_submission_integrity.sql"
SUPERVISOR_MIGRATION="supabase/migrations/202608231245_supervisor_site_assignment_control.sql"
SHIFT_DELETE_MIGRATION="supabase/migrations/202608232045_shift_deletion_integrity.sql"
WORKER_DELETE_MIGRATION="supabase/migrations/202608232118_worker_account_hard_delete_guard.sql"
PAYROLL_EXPORT_MIGRATION="supabase/migrations/202608232245_payroll_legacy_export_rpc_retirement.sql"

# Worker timesheet submission must stay server-authoritative, monotonic and
# derived only from trusted worker-app attendance.
test -f "$TIMESHEET_MIGRATION"
grep -q 'security definer' "$TIMESHEET_MIGRATION"
grep -q 'set search_path = public' "$TIMESHEET_MIGRATION"
grep -q 'accepted_at is not null' "$TIMESHEET_MIGRATION"
grep -q 'cancelled_at is null' "$TIMESHEET_MIGRATION"
grep -q 'for update of a' "$TIMESHEET_MIGRATION"
grep -q "v_status in ('approved','payroll_ready')" "$TIMESHEET_MIGRATION"
grep -q 'within_geofence is true' "$TIMESHEET_MIGRATION"
grep -q "te.source = 'worker_app'" "$TIMESHEET_MIGRATION"
grep -q 'te.created_by = v_worker' "$TIMESHEET_MIGRATION"
grep -q 'v_minutes > 1440' "$TIMESHEET_MIGRATION"
grep -q 'revoke all on function public.submit_timesheet(uuid) from public' "$TIMESHEET_MIGRATION"
test -f supabase/tests/timesheet_submission_integrity_checks.sql

# Supervisor-to-site scope is an authorization boundary. Direct authenticated
# mutation must remain revoked and changes must go through audited Ops/Admin RPCs.
test -f "$SUPERVISOR_MIGRATION"
grep -q 'revoke insert, update, delete on public.supervisor_sites from authenticated' "$SUPERVISOR_MIGRATION"
grep -q 'public.is_ops()' "$SUPERVISOR_MIGRATION"
grep -q "v_supervisor_role <> 'supervisor'" "$SUPERVISOR_MIGRATION"
grep -q 'cannot assign inactive site' "$SUPERVISOR_MIGRATION"
grep -q 'assignment reason required' "$SUPERVISOR_MIGRATION"
grep -q 'revocation reason required' "$SUPERVISOR_MIGRATION"
grep -q "'supervisor_site.assigned'" "$SUPERVISOR_MIGRATION"
grep -q "'supervisor_site.revoked'" "$SUPERVISOR_MIGRATION"
grep -q 'revoke all on function public.assign_supervisor_site(uuid,uuid,text) from public' "$SUPERVISOR_MIGRATION"
grep -q 'revoke all on function public.revoke_supervisor_site(uuid,uuid,text) from public' "$SUPERVISOR_MIGRATION"
test -f supabase/tests/supervisor_site_assignment_control_checks.sql

# Shift rows are historical anchors for assignments, attendance, timesheets and
# payroll. API users must cancel rather than physically delete them.
test -f "$SHIFT_DELETE_MIGRATION"
grep -q 'revoke delete on table public.shifts from authenticated, anon' "$SHIFT_DELETE_MIGRATION"
grep -q 'create trigger prevent_authenticated_shift_delete' "$SHIFT_DELETE_MIGRATION"
grep -q 'before delete on public.shifts' "$SHIFT_DELETE_MIGRATION"
grep -q 'auth.uid() is not null' "$SHIFT_DELETE_MIGRATION"
grep -q 'set search_path = pg_catalog, public' "$SHIFT_DELETE_MIGRATION"
grep -q 'revoke all on function public.prevent_authenticated_shift_delete() from public' "$SHIFT_DELETE_MIGRATION"
if grep -q 'security definer' "$SHIFT_DELETE_MIGRATION"; then
  echo 'shift deletion guard must not use SECURITY DEFINER' >&2
  exit 1
fi
test -f supabase/tests/shift_deletion_integrity_checks.sql

# Worker auth/profile deletion must not cascade away payroll, dispute, identity,
# attendance or retention evidence. Erasure stays inside the privacy/retention flow.
test -f "$WORKER_DELETE_MIGRATION"
grep -q 'security definer' "$WORKER_DELETE_MIGRATION"
grep -q 'set search_path = pg_catalog, public' "$WORKER_DELETE_MIGRATION"
grep -q 'from public.worker_profiles' "$WORKER_DELETE_MIGRATION"
grep -q 'before delete on public.profiles' "$WORKER_DELETE_MIGRATION"
grep -q 'revoke delete on public.profiles from anon, authenticated' "$WORKER_DELETE_MIGRATION"
grep -q 'revoke delete on public.worker_profiles from anon, authenticated' "$WORKER_DELETE_MIGRATION"
grep -q 'revoke all on function public.prevent_worker_profile_hard_delete() from authenticated' "$WORKER_DELETE_MIGRATION"
if grep -q 'allow_worker_hard_delete' "$WORKER_DELETE_MIGRATION"; then
  echo 'worker hard-delete guard must not expose a session-setting bypass' >&2
  exit 1
fi
test -f supabase/tests/worker_account_hard_delete_guard_checks.sql

# Payroll export must require immutable export evidence. The legacy one-argument
# transition is retained only for migration compatibility and must not be callable.
test -f "$PAYROLL_EXPORT_MIGRATION"
grep -q 'revoke all on function public.mark_payroll_batch_exported(uuid) from public' "$PAYROLL_EXPORT_MIGRATION"
grep -q 'revoke all on function public.mark_payroll_batch_exported(uuid) from anon' "$PAYROLL_EXPORT_MIGRATION"
grep -q 'revoke all on function public.mark_payroll_batch_exported(uuid) from authenticated' "$PAYROLL_EXPORT_MIGRATION"
grep -q 'grant execute on function public.record_payroll_export(uuid,text,text,integer) to authenticated' "$PAYROLL_EXPORT_MIGRATION"
test -f supabase/tests/payroll_legacy_export_rpc_retirement_checks.sql

echo 'Critical timesheet, supervisor authorization, shift-history, worker lifecycle and payroll export invariants present.'
