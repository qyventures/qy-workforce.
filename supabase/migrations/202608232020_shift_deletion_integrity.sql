-- Preserve assignment, attendance, timesheet and payroll history by preventing
-- authenticated users from physically deleting shifts. Operational removal is
-- represented by the existing cancelled state instead.

create or replace function public.prevent_authenticated_shift_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- auth.uid() is populated for Supabase API requests. Keep service/database
  -- maintenance possible when there is no authenticated end-user context.
  if auth.uid() is not null then
    raise exception 'shifts cannot be deleted; cancel the shift instead'
      using errcode = '42501';
  end if;

  return old;
end;
$$;

revoke all on function public.prevent_authenticated_shift_delete() from public;

-- RLS already limits shift management to Ops/Admin, but the broad FOR ALL policy
-- historically included DELETE. Explicit privilege revocation plus a trigger gives
-- defence in depth and protects against future policy broadening.
revoke delete on table public.shifts from authenticated, anon;

drop trigger if exists prevent_authenticated_shift_delete on public.shifts;
create trigger prevent_authenticated_shift_delete
before delete on public.shifts
for each row
execute function public.prevent_authenticated_shift_delete();

comment on function public.prevent_authenticated_shift_delete() is
  'Prevents authenticated API users from physically deleting shifts and cascading away assignment/attendance/timesheet history. Use shift status=cancelled instead.';

comment on trigger prevent_authenticated_shift_delete on public.shifts is
  'Protects immutable workforce history from destructive authenticated shift deletion.';
