-- Enforce matching and capacity invariants at the assignment table boundary.
-- This is defense in depth for future privileged RPCs and backend integrations:
-- every insert/reactivation must meet the same rules as accept_shift().

create or replace function public.guard_shift_assignment_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_role_active boolean;
  v_site_active boolean;
  v_client_active boolean;
  v_active_count integer;
begin
  -- Cancellation-only updates do not consume capacity.
  if tg_op = 'UPDATE'
     and old.cancelled_at is null
     and new.cancelled_at is not null then
    if new.shift_id is distinct from old.shift_id
       or new.worker_id is distinct from old.worker_id
       or new.accepted_at is distinct from old.accepted_at then
      raise exception 'assignment identity and acceptance are immutable';
    end if;
    if new.cancelled_at < old.accepted_at then
      raise exception 'cancellation cannot precede acceptance';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.shift_id is distinct from old.shift_id then
    raise exception 'assignment shift is immutable';
  end if;
  if tg_op = 'UPDATE'
     and new.worker_id is distinct from old.worker_id then
    raise exception 'assignment worker is immutable';
  end if;

  -- No capacity is consumed while the row remains cancelled.
  if new.cancelled_at is not null then
    if new.accepted_at is null or new.cancelled_at < new.accepted_at then
      raise exception 'invalid cancelled assignment chronology';
    end if;
    return new;
  end if;

  if new.accepted_at is null then
    raise exception 'active assignment requires acceptance timestamp';
  end if;

  -- Serialize every activation for a shift and for a worker, even if the write
  -- did not originate in accept_shift(). Lock order matches accept_shift().
  perform pg_advisory_xact_lock(hashtextextended(new.worker_id::text, 0));

  select sh, r.active, s.active, c.active
    into v_shift, v_role_active, v_site_active, v_client_active
  from public.shifts sh
  join public.roles r on r.id = sh.role_id
  join public.sites s on s.id = sh.site_id
  join public.clients c on c.id = s.client_id
  where sh.id = new.shift_id
  for update of sh;

  if not found
     or v_shift.status <> 'open'
     or v_shift.starts_at <= now()
     or not v_role_active
     or not v_site_active
     or not v_client_active then
    raise exception 'shift unavailable';
  end if;

  if not public.worker_has_deployment_prerequisites(new.worker_id) then
    raise exception 'worker is not currently deployable';
  end if;
  if not public.worker_is_available_for_shift(
    new.worker_id, v_shift.starts_at, v_shift.ends_at
  ) then
    raise exception 'worker unavailable for shift';
  end if;
  if not exists (
    select 1
    from public.worker_roles wr
    where wr.worker_id = new.worker_id
      and wr.role_id = v_shift.role_id
      and wr.approved
  ) then
    raise exception 'role not approved';
  end if;
  if exists (
    select 1
    from public.shift_assignments a
    join public.shifts existing on existing.id = a.shift_id
    where a.worker_id = new.worker_id
      and a.id <> new.id
      and a.cancelled_at is null
      and existing.status <> 'cancelled'
      and existing.starts_at < v_shift.ends_at
      and existing.ends_at > v_shift.starts_at
  ) then
    raise exception 'worker has overlapping shift';
  end if;

  select count(*)::integer
    into v_active_count
  from public.shift_assignments a
  where a.shift_id = new.shift_id
    and a.id <> new.id
    and a.cancelled_at is null;

  if v_active_count >= v_shift.headcount then
    raise exception 'shift full';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_shift_assignment_activation
  on public.shift_assignments;
create trigger trg_guard_shift_assignment_activation
before insert or update of shift_id, worker_id, accepted_at, cancelled_at
on public.shift_assignments
for each row execute function public.guard_shift_assignment_activation();

revoke all on function public.guard_shift_assignment_activation()
  from public, anon, authenticated;

comment on function public.guard_shift_assignment_activation() is
'Table-level assignment activation invariant: locks worker and shift, enforces live readiness, availability, approved role, no overlap and remaining capacity, while keeping identity, residency and work eligibility as separate prerequisite inputs.';
