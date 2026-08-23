-- Preserve assignment, attendance, timesheet and payroll history by preventing
-- API users from physically deleting shifts. Operational removal must use the
-- existing cancelled state so downstream audit/payroll history remains intact.

create or replace function public.prevent_authenticated_shift_delete()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  -- Supabase API requests carry auth.uid(). Database/service maintenance with no
  -- authenticated end-user context remains possible for controlled operations.
  if auth.uid() is not null then
    raise exception 'shifts cannot be deleted; cancel the shift instead'
      using errcode = '42501';
  end if;

  return old;
end;
$$;

revoke all on function public.prevent_authenticated_shift_delete() from public;

-- Defence in depth: RLS/policies may change over time, but API roles must never
-- regain destructive DELETE access to workforce history.
revoke delete on table public.shifts from authenticated, anon;

drop trigger if exists prevent_authenticated_shift_delete on public.shifts;
create trigger prevent_authenticated_shift_delete
before delete on public.shifts
for each row
execute function public.prevent_authenticated_shift_delete();

comment on function public.prevent_authenticated_shift_delete() is
  'Rejects authenticated API deletion of shifts. Cancel shifts instead to preserve assignment, attendance, timesheet and payroll history.';

comment on trigger prevent_authenticated_shift_delete on public.shifts is
  'Protects workforce history from destructive authenticated shift deletion.';
