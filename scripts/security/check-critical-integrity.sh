#!/usr/bin/env bash
set -euo pipefail

TIMESHEET_MIGRATION="supabase/migrations/202608231147_timesheet_submission_integrity.sql"
SUPERVISOR_MIGRATION="supabase/migrations/202608231245_supervisor_site_assignment_control.sql"

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

echo 'Critical timesheet and supervisor authorization invariants present.'
