-- Harden worker shift acceptance against overlap races and stale/past demand.
-- Capacity remains serialized by locking the target shift row; worker-level acceptance
-- is serialized with a transaction advisory lock so concurrent accepts for different
-- overlapping shifts cannot both succeed for the same worker.

create or replace function public.accept_shift(p_shift_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_worker uuid := auth.uid();
  v_role uuid;
  v_status public.shift_status;
  v_headcount integer;
  v_taken integer;
  v_worker_status public.worker_status;
  v_assignment uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
begin
  if v_worker is null then
    raise exception 'authentication required';
  end if;

  -- Serialize all acceptance attempts for this worker, even when they target
  -- different shifts, before checking for schedule overlap.
  perform pg_advisory_xact_lock(hashtextextended(v_worker::text, 0));

  select role_id,status,headcount,starts_at,ends_at
    into v_role,v_status,v_headcount,v_starts_at,v_ends_at
  from public.shifts
  where id=p_shift_id
  for update;

  if not found then raise exception 'shift unavailable'; end if;
  if v_status <> 'open' then raise exception 'shift unavailable'; end if;
  if v_starts_at <= now() then raise exception 'shift already started'; end if;

  select status into v_worker_status
  from public.worker_profiles
  where user_id=v_worker;

  if v_worker_status <> 'deployable' then
    raise exception 'worker not deployable';
  end if;

  if not exists(
    select 1 from public.worker_roles
    where worker_id=v_worker and role_id=v_role and approved=true
  ) then
    raise exception 'role not approved';
  end if;

  -- Reject overlapping active assignments. Cancelled shifts/assignments do not
  -- block the worker. Touching boundaries are allowed (end == next start).
  if exists (
    select 1
    from public.shift_assignments a
    join public.shifts sh on sh.id=a.shift_id
    where a.worker_id=v_worker
      and a.cancelled_at is null
      and a.shift_id <> p_shift_id
      and sh.status <> 'cancelled'
      and sh.starts_at < v_ends_at
      and sh.ends_at > v_starts_at
  ) then
    raise exception 'worker has overlapping shift';
  end if;

  -- The target shift row is locked above, so concurrent accepts for this shift
  -- cannot oversubscribe headcount.
  select count(*) into v_taken
  from public.shift_assignments
  where shift_id=p_shift_id and cancelled_at is null;

  if v_taken >= v_headcount then raise exception 'shift full'; end if;

  insert into public.shift_assignments(shift_id,worker_id,accepted_at)
  values(p_shift_id,v_worker,now())
  on conflict(shift_id,worker_id) do update
    set accepted_at=excluded.accepted_at,
        cancelled_at=null
  returning id into v_assignment;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(
    v_worker,
    'shift.accepted',
    'shift_assignment',
    v_assignment,
    jsonb_build_object(
      'shift_id',p_shift_id,
      'starts_at',v_starts_at,
      'ends_at',v_ends_at,
      'capacity',v_headcount,
      'active_assignments_before_accept',v_taken
    )
  );

  return v_assignment;
end;
$$;

revoke all on function public.accept_shift(uuid) from public;
grant execute on function public.accept_shift(uuid) to authenticated;

comment on function public.accept_shift(uuid) is
'Worker-only secure shift acceptance. Serializes worker acceptance, locks shift capacity, rejects past/non-open shifts and schedule overlaps, and audits successful acceptance.';
