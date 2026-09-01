-- Keep shift discovery and acceptance aligned with the live readiness boundary.
-- Availability and absences are operational scheduling signals, not identity,
-- residency, or work-eligibility evidence.

create or replace function public.worker_is_available_for_shift(
  p_worker_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_worker_id is not null
    and p_starts_at is not null
    and p_ends_at is not null
    and p_ends_at > p_starts_at
    and not exists (
      select 1
      from public.worker_availability wa
      where wa.worker_id = p_worker_id
        and wa.availability_type = 'unavailable'
        and wa.starts_at < p_ends_at
        and wa.ends_at > p_starts_at
    )
    and not exists (
      select 1
      from public.worker_absences ab
      where ab.worker_id = p_worker_id
        and ab.status in ('reported', 'reviewed', 'approved')
        and ab.starts_at < p_ends_at
        and ab.ends_at > p_starts_at
    );
$$;
revoke all on function public.worker_is_available_for_shift(uuid,timestamptz,timestamptz)
  from public, anon, authenticated;

create or replace function public.accept_shift(p_shift_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid := auth.uid();
  v_role uuid;
  v_status public.shift_status;
  v_headcount integer;
  v_taken integer;
  v_assignment uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_role_active boolean;
  v_site_active boolean;
  v_client_active boolean;
begin
  if v_worker is null then
    raise exception 'authentication required';
  end if;

  -- Serializes accepts/cancellations across overlapping shifts for one worker.
  perform pg_advisory_xact_lock(hashtextextended(v_worker::text, 0));

  select sh.role_id, sh.status, sh.headcount, sh.starts_at, sh.ends_at,
         r.active, s.active, c.active
    into v_role, v_status, v_headcount, v_starts_at, v_ends_at,
         v_role_active, v_site_active, v_client_active
  from public.shifts sh
  join public.roles r on r.id = sh.role_id
  join public.sites s on s.id = sh.site_id
  join public.clients c on c.id = s.client_id
  where sh.id = p_shift_id
  for update of sh;

  if not found or v_status <> 'open' or v_starts_at <= now() then
    raise exception 'shift unavailable';
  end if;
  if not v_role_active or not v_site_active or not v_client_active then
    raise exception 'shift unavailable';
  end if;
  if not public.worker_has_deployment_prerequisites(v_worker) then
    raise exception 'worker is not currently deployable';
  end if;
  if not public.worker_is_available_for_shift(v_worker, v_starts_at, v_ends_at) then
    raise exception 'worker unavailable for shift';
  end if;
  if not exists (
    select 1
    from public.worker_roles wr
    where wr.worker_id = v_worker and wr.role_id = v_role and wr.approved
  ) then
    raise exception 'role not approved';
  end if;
  if exists (
    select 1
    from public.shift_assignments a
    join public.shifts sh on sh.id = a.shift_id
    where a.worker_id = v_worker
      and a.cancelled_at is null
      and a.shift_id <> p_shift_id
      and sh.status <> 'cancelled'
      and sh.starts_at < v_ends_at
      and sh.ends_at > v_starts_at
  ) then
    raise exception 'worker has overlapping shift';
  end if;

  select count(*) into v_taken
  from public.shift_assignments
  where shift_id = p_shift_id and cancelled_at is null;
  if v_taken >= v_headcount then
    raise exception 'shift full';
  end if;

  insert into public.shift_assignments(shift_id,worker_id,accepted_at)
  values(p_shift_id,v_worker,now())
  on conflict(shift_id,worker_id) do update
    set accepted_at = excluded.accepted_at,
        cancelled_at = null
  returning id into v_assignment;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(
    v_worker, 'shift.accepted', 'shift_assignment', v_assignment,
    jsonb_build_object('shift_id',p_shift_id, 'starts_at',v_starts_at,
      'ends_at',v_ends_at, 'capacity',v_headcount,
      'active_assignments_before_accept',v_taken)
  );
  return v_assignment;
end;
$$;
revoke all on function public.accept_shift(uuid) from public;
grant execute on function public.accept_shift(uuid) to authenticated;

create or replace function public.get_available_shifts()
returns table (
  shift_id uuid,
  role_name text,
  client_name text,
  site_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  worker_rate numeric,
  requirements jsonb,
  available_slots integer
)
language plpgsql
security definer
stable
set search_path=public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if not public.worker_has_deployment_prerequisites(auth.uid()) then
    return;
  end if;

  return query
  select sh.id, r.name, c.name, s.name, sh.starts_at, sh.ends_at,
         sh.worker_rate, coalesce(sh.requirements, '{}'::jsonb),
         greatest(sh.headcount - (
           select count(*)::integer from public.shift_assignments a
           where a.shift_id=sh.id and a.cancelled_at is null
         ), 0)
  from public.shifts sh
  join public.roles r on r.id=sh.role_id
  join public.sites s on s.id=sh.site_id
  join public.clients c on c.id=s.client_id
  where sh.status='open'
    and sh.starts_at > now()
    and r.active and s.active and c.active
    and public.worker_is_available_for_shift(auth.uid(), sh.starts_at, sh.ends_at)
    and exists (
      select 1 from public.worker_roles wr
      where wr.worker_id=auth.uid() and wr.role_id=sh.role_id and wr.approved
    )
    and not exists (
      select 1 from public.shift_assignments mine
      where mine.shift_id=sh.id and mine.worker_id=auth.uid()
        and mine.cancelled_at is null
    )
    and not exists (
      select 1 from public.shift_assignments mine
      join public.shifts existing on existing.id=mine.shift_id
      where mine.worker_id=auth.uid() and mine.cancelled_at is null
        and existing.status <> 'cancelled'
        and existing.starts_at < sh.ends_at and existing.ends_at > sh.starts_at
    )
    and (
      select count(*) from public.shift_assignments active
      where active.shift_id=sh.id and active.cancelled_at is null
    ) < sh.headcount
  order by sh.starts_at asc
  limit 100;
end;
$$;
revoke all on function public.get_available_shifts() from public;
grant execute on function public.get_available_shifts() to authenticated;

comment on function public.worker_is_available_for_shift(uuid,timestamptz,timestamptz) is
  'Internal scheduling predicate. Blocks overlapping unavailable windows and non-terminal absences without exposing absence details.';
comment on function public.accept_shift(uuid) is
  'Worker-only acceptance boundary: locks worker/capacity, requires live readiness and scheduling availability, and rejects inactive demand.';
