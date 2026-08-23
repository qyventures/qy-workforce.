-- QY Workforce: require live deployability at worker clock-in.
-- Acceptance-time checks are not sufficient because vetting, training, residency,
-- work eligibility or consent can expire/revoke before the shift begins.
-- Clock-out remains allowed so a worker can close attendance already started.

create or replace function public.guard_worker_clock_in_deployability()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid;
begin
  if new.source is distinct from 'worker_app' or new.event_type is distinct from 'clock_in' then
    return new;
  end if;

  select sa.worker_id into v_worker
  from public.shift_assignments sa
  where sa.id = new.assignment_id
    and sa.accepted_at is not null
    and sa.cancelled_at is null;

  if v_worker is null then
    raise exception 'active assignment required';
  end if;

  if new.created_by is distinct from v_worker then
    raise exception 'attendance actor does not match assigned worker';
  end if;

  if auth.uid() is not null and auth.uid() is distinct from v_worker then
    raise exception 'attendance actor does not match authenticated worker';
  end if;

  if not public.worker_has_deployment_prerequisites(v_worker) then
    raise exception 'worker is not currently deployable';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_worker_clock_in_deployability() from public;

drop trigger if exists time_events_worker_clock_in_deployability_guard on public.time_events;
create trigger time_events_worker_clock_in_deployability_guard
before insert on public.time_events
for each row execute function public.guard_worker_clock_in_deployability();

comment on function public.guard_worker_clock_in_deployability() is
'Blocks worker-app clock-in unless the assigned worker still satisfies live deployment prerequisites. Clock-out is intentionally not blocked by later expiry/revocation.';
