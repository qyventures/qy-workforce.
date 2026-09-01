-- Keep every deployable-worker decision behind the same final, Ops-managed gate.
-- worker_has_deployment_prerequisites() evaluates independent identity, residency,
-- eligibility, vetting, training and consent facts. worker_is_deployable() adds
-- the explicit Operations status gate; neither function collapses those domains.

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
  if v_worker is null then raise exception 'authentication required'; end if;
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

  if not found or v_status <> 'open' or v_starts_at <= now()
     or not v_role_active or not v_site_active or not v_client_active then
    raise exception 'shift unavailable';
  end if;
  if not public.worker_is_deployable(v_worker) then
    raise exception 'worker is not currently deployable';
  end if;
  if not public.worker_is_available_for_shift(v_worker, v_starts_at, v_ends_at) then
    raise exception 'worker unavailable for shift';
  end if;
  if not exists (
    select 1 from public.worker_roles wr
    where wr.worker_id = v_worker and wr.role_id = v_role and wr.approved
  ) then raise exception 'role not approved'; end if;
  if exists (
    select 1 from public.shift_assignments a
    join public.shifts sh on sh.id = a.shift_id
    where a.worker_id = v_worker and a.cancelled_at is null and a.shift_id <> p_shift_id
      and sh.status <> 'cancelled' and sh.starts_at < v_ends_at and sh.ends_at > v_starts_at
  ) then raise exception 'worker has overlapping shift'; end if;

  select count(*) into v_taken from public.shift_assignments
  where shift_id = p_shift_id and cancelled_at is null;
  if v_taken >= v_headcount then raise exception 'shift full'; end if;

  insert into public.shift_assignments(shift_id, worker_id, accepted_at)
  values(p_shift_id, v_worker, now())
  on conflict(shift_id, worker_id) do update
    set accepted_at = excluded.accepted_at, cancelled_at = null
  returning id into v_assignment;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(v_worker, 'shift.accepted', 'shift_assignment', v_assignment,
    jsonb_build_object('shift_id', p_shift_id, 'starts_at', v_starts_at,
      'ends_at', v_ends_at, 'capacity', v_headcount,
      'active_assignments_before_accept', v_taken, 'live_deployability_checked', true));
  return v_assignment;
end;
$$;
revoke all on function public.accept_shift(uuid) from public;
grant execute on function public.accept_shift(uuid) to authenticated;

create or replace function public.get_available_shifts()
returns table (
  shift_id uuid, role_name text, client_name text, site_name text,
  starts_at timestamptz, ends_at timestamptz, worker_rate numeric,
  requirements jsonb, available_slots integer
)
language plpgsql security definer stable set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.worker_is_deployable(auth.uid()) then return; end if;
  return query
  select sh.id, r.name, c.name, s.name, sh.starts_at, sh.ends_at, sh.worker_rate,
         coalesce(sh.requirements, '{}'::jsonb),
         greatest(sh.headcount - (select count(*)::integer from public.shift_assignments a
           where a.shift_id = sh.id and a.cancelled_at is null), 0)
  from public.shifts sh
  join public.roles r on r.id = sh.role_id
  join public.sites s on s.id = sh.site_id
  join public.clients c on c.id = s.client_id
  where sh.status = 'open' and sh.starts_at > now() and r.active and s.active and c.active
    and public.worker_is_available_for_shift(auth.uid(), sh.starts_at, sh.ends_at)
    and exists (select 1 from public.worker_roles wr
      where wr.worker_id = auth.uid() and wr.role_id = sh.role_id and wr.approved)
    and not exists (select 1 from public.shift_assignments mine
      where mine.shift_id = sh.id and mine.worker_id = auth.uid() and mine.cancelled_at is null)
    and not exists (select 1 from public.shift_assignments mine
      join public.shifts existing on existing.id = mine.shift_id
      where mine.worker_id = auth.uid() and mine.cancelled_at is null
        and existing.status <> 'cancelled'
        and existing.starts_at < sh.ends_at and existing.ends_at > sh.starts_at)
    and (select count(*) from public.shift_assignments active
      where active.shift_id = sh.id and active.cancelled_at is null) < sh.headcount
  order by sh.starts_at asc limit 100;
end;
$$;
revoke all on function public.get_available_shifts() from public;
grant execute on function public.get_available_shifts() to authenticated;

create or replace function public.guard_worker_clock_in_deployability()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_worker uuid;
begin
  if new.source is distinct from 'worker_app' or new.event_type is distinct from 'clock_in' then return new; end if;
  select sa.worker_id into v_worker from public.shift_assignments sa
  where sa.id = new.assignment_id and sa.accepted_at is not null and sa.cancelled_at is null;
  if v_worker is null then raise exception 'active assignment required'; end if;
  if new.created_by is distinct from v_worker then raise exception 'attendance actor does not match assigned worker'; end if;
  if auth.uid() is not null and auth.uid() is distinct from v_worker then raise exception 'attendance actor does not match authenticated worker'; end if;
  if not public.worker_is_deployable(v_worker) then raise exception 'worker is not currently deployable'; end if;
  return new;
end;
$$;
revoke all on function public.guard_worker_clock_in_deployability() from public, anon, authenticated;

create or replace function public.guard_shift_assignment_activation()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_role_active boolean;
  v_site_active boolean;
  v_client_active boolean;
  v_active_count integer;
begin
  if tg_op = 'UPDATE' and old.cancelled_at is null and new.cancelled_at is not null then
    if new.shift_id is distinct from old.shift_id or new.worker_id is distinct from old.worker_id
       or new.accepted_at is distinct from old.accepted_at then raise exception 'assignment identity and acceptance are immutable'; end if;
    if new.cancelled_at < old.accepted_at then raise exception 'cancellation cannot precede acceptance'; end if;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.shift_id is distinct from old.shift_id then raise exception 'assignment shift is immutable'; end if;
  if tg_op = 'UPDATE' and new.worker_id is distinct from old.worker_id then raise exception 'assignment worker is immutable'; end if;
  if new.cancelled_at is not null then
    if new.accepted_at is null or new.cancelled_at < new.accepted_at then raise exception 'invalid cancelled assignment chronology'; end if;
    return new;
  end if;
  if new.accepted_at is null then raise exception 'active assignment requires acceptance timestamp'; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.worker_id::text, 0));
  select sh, r.active, s.active, c.active into v_shift, v_role_active, v_site_active, v_client_active
  from public.shifts sh join public.roles r on r.id = sh.role_id
  join public.sites s on s.id = sh.site_id join public.clients c on c.id = s.client_id
  where sh.id = new.shift_id for update of sh;
  if not found or v_shift.status <> 'open' or v_shift.starts_at <= now()
     or not v_role_active or not v_site_active or not v_client_active then raise exception 'shift unavailable'; end if;
  if not public.worker_is_deployable(new.worker_id) then raise exception 'worker is not currently deployable'; end if;
  if not public.worker_is_available_for_shift(new.worker_id, v_shift.starts_at, v_shift.ends_at) then raise exception 'worker unavailable for shift'; end if;
  if not exists (select 1 from public.worker_roles wr where wr.worker_id = new.worker_id
                 and wr.role_id = v_shift.role_id and wr.approved) then raise exception 'role not approved'; end if;
  if exists (select 1 from public.shift_assignments a join public.shifts existing on existing.id = a.shift_id
    where a.worker_id = new.worker_id and a.id <> new.id and a.cancelled_at is null
      and existing.status <> 'cancelled' and existing.starts_at < v_shift.ends_at and existing.ends_at > v_shift.starts_at)
  then raise exception 'worker has overlapping shift'; end if;
  select count(*)::integer into v_active_count from public.shift_assignments a
  where a.shift_id = new.shift_id and a.id <> new.id and a.cancelled_at is null;
  if v_active_count >= v_shift.headcount then raise exception 'shift full'; end if;
  return new;
end;
$$;
revoke all on function public.guard_shift_assignment_activation() from public, anon, authenticated;

create or replace function public.get_ops_replacement_candidates(p_shift_id uuid, p_limit integer default 20)
returns table(worker_id uuid, worker_name text, reliability_score integer, preferred_available boolean, available_cover boolean)
language plpgsql security definer stable set search_path = public
as $$
declare v_role uuid; v_starts timestamptz; v_ends timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then raise exception 'invalid candidate limit'; end if;
  select role_id, starts_at, ends_at into v_role, v_starts, v_ends from public.shifts
    where id = p_shift_id and status in ('open','assigned');
  if v_role is null then raise exception 'shift not found or not fillable'; end if;
  return query
  with eligible as (
    select wp.user_id, coalesce(p.display_name, 'Worker') worker_name,
           greatest(0, least(100, 80 + coalesce(sum(wre.points) filter (where wre.created_at >= now() - interval '180 days'), 0)))::integer reliability_score,
           exists(select 1 from public.worker_availability wa where wa.worker_id = wp.user_id and wa.availability_type = 'preferred' and wa.starts_at <= v_starts and wa.ends_at >= v_ends) preferred_available,
           exists(select 1 from public.worker_availability wa where wa.worker_id = wp.user_id and wa.availability_type in ('available','preferred') and wa.starts_at <= v_starts and wa.ends_at >= v_ends) available_cover
      from public.worker_profiles wp join public.profiles p on p.id = wp.user_id
      join public.worker_roles wr on wr.worker_id = wp.user_id and wr.role_id = v_role and wr.approved
      left join public.worker_reliability_events wre on wre.worker_id = wp.user_id
     where public.worker_is_deployable(wp.user_id)
       and public.worker_is_available_for_shift(wp.user_id, v_starts, v_ends)
       and not exists (select 1 from public.shift_assignments sa
         join public.shifts sh on sh.id = sa.shift_id
         where sa.worker_id = wp.user_id and sa.cancelled_at is null
           and sh.status <> 'cancelled'
           and sh.starts_at < v_ends and sh.ends_at > v_starts)
       and not exists (select 1 from public.shift_assignments sa where sa.shift_id = p_shift_id and sa.worker_id = wp.user_id and sa.cancelled_at is null)
     group by wp.user_id, p.display_name
  ) select e.user_id, e.worker_name, e.reliability_score, e.preferred_available, e.available_cover
      from eligible e order by e.preferred_available desc, e.available_cover desc, e.reliability_score desc, e.worker_name limit p_limit;
end;
$$;
revoke all on function public.get_ops_replacement_candidates(uuid,integer) from public;
grant execute on function public.get_ops_replacement_candidates(uuid,integer) to authenticated;

comment on function public.worker_is_deployable(uuid) is
  'Final deployability predicate. Requires the Ops-managed deployable status plus independent, live identity, residency, work-eligibility, vetting, training and consent prerequisites.';
comment on function public.get_ops_replacement_candidates(uuid,integer) is
  'Ops-only replacement suggestions. Candidates meet the final live deployability and availability checks but still require an explicit assignment action.';
