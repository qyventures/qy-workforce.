-- QY Workforce: freeze worker-facing/commercial shift terms once a worker has accepted.
-- This prevents post-acceptance edits from silently changing pay, billing, role, site or schedule.

create or replace function public.guard_accepted_shift_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_assignments integer;
begin
  select count(*)::integer
    into v_active_assignments
  from public.shift_assignments a
  where a.shift_id = old.id
    and a.accepted_at is not null
    and a.cancelled_at is null;

  if v_active_assignments > 0 then
    if new.site_id is distinct from old.site_id
       or new.role_id is distinct from old.role_id
       or new.starts_at is distinct from old.starts_at
       or new.ends_at is distinct from old.ends_at
       or new.worker_rate is distinct from old.worker_rate
       or new.client_rate is distinct from old.client_rate then
      raise exception 'accepted shift terms are immutable';
    end if;

    if new.headcount < v_active_assignments then
      raise exception 'headcount cannot be lower than active accepted assignments';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_accepted_shift_terms on public.shifts;
create trigger trg_guard_accepted_shift_terms
before update on public.shifts
for each row execute function public.guard_accepted_shift_terms();

revoke all on function public.guard_accepted_shift_terms() from public;

comment on function public.guard_accepted_shift_terms() is
'Prevents post-acceptance edits to site, role, schedule and rates; capacity cannot drop below active accepted assignments.';
