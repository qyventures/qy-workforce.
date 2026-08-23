-- QY Workforce V1: preserve the approved financial basis used for payroll and margin reporting.
-- Once a supervisor/ops reviewer approves a timesheet, its attendance-derived minutes and
-- amounts must not be silently rewritten by ordinary SQL or a later application bug.

create or replace function public.guard_approved_timesheet_financial_basis()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Approval is the financial control point. Payroll locking may legitimately advance
  -- status from approved -> payroll_ready, but it must not alter the approved basis.
  if old.status::text in ('approved','payroll_ready') then
    if new.assignment_id is distinct from old.assignment_id
       or new.payable_minutes is distinct from old.payable_minutes
       or new.worker_amount is distinct from old.worker_amount
       or new.client_amount is distinct from old.client_amount then
      raise exception 'approved timesheet financial basis is immutable';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists timesheets_guard_approved_financial_basis on public.timesheets;
create trigger timesheets_guard_approved_financial_basis
before update on public.timesheets
for each row execute function public.guard_approved_timesheet_financial_basis();

comment on function public.guard_approved_timesheet_financial_basis() is
  'Prevents changes to assignment, payable minutes, worker amount or client amount after supervisor approval/payroll readiness.';
