-- QY Workforce: live deployability guard.
-- A stored worker_profiles.status='deployable' remains the final Ops gate, but it is
-- never sufficient by itself. Consent withdrawal, eligibility changes, vetting
-- exceptions, or required-training expiry immediately remove shift eligibility.

create or replace function public.worker_has_deployment_prerequisites(p_worker_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select
      wp.identity_verified
      and wp.residency_verified
      and wp.work_eligibility = 'eligible'
      and wp.status not in ('suspended','rejected')
      and exists (
        select 1
        from public.worker_roles wr
        join public.roles r on r.id = wr.role_id
        where wr.worker_id = wp.user_id
          and wr.approved = true
          and r.active = true
      )
      and not exists (
        select 1
        from public.worker_vetting wv
        where wv.worker_id = wp.user_id
          and wv.status in ('pending','failed','manual_review')
      )
      and not exists (
        select 1
        from public.training_modules tm
        where tm.active = true
          and (
            tm.role_id is null
            or exists (
              select 1
              from public.worker_roles wr
              where wr.worker_id = wp.user_id
                and wr.role_id = tm.role_id
                and wr.approved = true
            )
          )
          and not exists (
            select 1
            from public.worker_training wt
            where wt.worker_id = wp.user_id
              and wt.module_id = tm.id
              and wt.status = 'passed'
              and (wt.expires_at is null or wt.expires_at > now())
          )
      )
      and exists (
        select 1 from public.worker_consents c
        where c.worker_id = wp.user_id
          and c.purpose = 'identity_verification'
          and c.granted = true
          and c.withdrawn_at is null
      )
      and exists (
        select 1 from public.worker_consents c
        where c.worker_id = wp.user_id
          and c.purpose = 'work_eligibility'
          and c.granted = true
          and c.withdrawn_at is null
      )
      and exists (
        select 1 from public.worker_consents c
        where c.worker_id = wp.user_id
          and c.purpose = 'location_clocking'
          and c.granted = true
          and c.withdrawn_at is null
      )
    from public.worker_profiles wp
    where wp.user_id = p_worker_id
  ), false);
$$;

revoke all on function public.worker_has_deployment_prerequisites(uuid) from public;

create or replace function public.worker_is_deployable(p_worker_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select wp.status = 'deployable'
      and public.worker_has_deployment_prerequisites(wp.user_id)
    from public.worker_profiles wp
    where wp.user_id = p_worker_id
  ), false);
$$;

revoke all on function public.worker_is_deployable(uuid) from public;

create or replace function public.get_worker_readiness()
returns table (
  worker_status public.worker_status,
  identity_verified boolean,
  residency_verified boolean,
  work_eligibility public.eligibility_status,
  approved_roles integer,
  verified_skills integer,
  outstanding_training integer,
  failed_vetting integer,
  required_consents_complete boolean,
  deployable boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select wp.* from public.worker_profiles wp where wp.user_id = auth.uid()
  ), role_count as (
    select count(*)::int as n
    from public.worker_roles wr join public.roles r on r.id=wr.role_id
    where wr.worker_id=auth.uid() and wr.approved and r.active
  ), skill_count as (
    select count(*)::int as n from public.worker_skills ws
    where ws.worker_id=auth.uid() and ws.verified
  ), training_count as (
    select count(*)::int as n
    from public.training_modules tm
    where tm.active
      and (tm.role_id is null or exists (
        select 1 from public.worker_roles wr
        where wr.worker_id=auth.uid() and wr.role_id=tm.role_id and wr.approved
      ))
      and not exists (
        select 1 from public.worker_training wt
        where wt.worker_id=auth.uid() and wt.module_id=tm.id
          and wt.status='passed' and (wt.expires_at is null or wt.expires_at > now())
      )
  ), vetting_count as (
    select count(*)::int as n from public.worker_vetting wv
    where wv.worker_id=auth.uid() and wv.status in ('failed','manual_review')
  ), consent_state as (
    select (
      exists(select 1 from public.worker_consents c where c.worker_id=auth.uid() and c.purpose='identity_verification' and c.granted and c.withdrawn_at is null)
      and exists(select 1 from public.worker_consents c where c.worker_id=auth.uid() and c.purpose='work_eligibility' and c.granted and c.withdrawn_at is null)
      and exists(select 1 from public.worker_consents c where c.worker_id=auth.uid() and c.purpose='location_clocking' and c.granted and c.withdrawn_at is null)
    ) as ok
  )
  select me.status, me.identity_verified, me.residency_verified, me.work_eligibility,
         role_count.n, skill_count.n, training_count.n, vetting_count.n,
         consent_state.ok, public.worker_is_deployable(auth.uid())
  from me, role_count, skill_count, training_count, vetting_count, consent_state;
$$;

revoke all on function public.get_worker_readiness() from public;
grant execute on function public.get_worker_readiness() to authenticated;

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
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.worker_is_deployable(auth.uid()) then return; end if;

  return query
  select sh.id, r.name, c.name, s.name, sh.starts_at, sh.ends_at, sh.worker_rate,
         coalesce(sh.requirements, '{}'::jsonb),
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
    and exists (
      select 1 from public.worker_roles wr
      where wr.worker_id=auth.uid() and wr.role_id=sh.role_id and wr.approved
    )
    and not exists (
      select 1 from public.shift_assignments mine
      where mine.shift_id=sh.id and mine.worker_id=auth.uid() and mine.cancelled_at is null
    )
    and (select count(*) from public.shift_assignments active where active.shift_id=sh.id and active.cancelled_at is null) < sh.headcount
  order by sh.starts_at asc
  limit 100;
end;
$$;

revoke all on function public.get_available_shifts() from public;
grant execute on function public.get_available_shifts() to authenticated;

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
  v_assignment uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
begin
  if v_worker is null then raise exception 'authentication required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_worker::text, 0));

  select role_id,status,headcount,starts_at,ends_at
    into v_role,v_status,v_headcount,v_starts_at,v_ends_at
  from public.shifts where id=p_shift_id for update;

  if not found or v_status <> 'open' then raise exception 'shift unavailable'; end if;
  if v_starts_at <= now() then raise exception 'shift already started'; end if;
  if not public.worker_is_deployable(v_worker) then raise exception 'worker not deployable'; end if;

  if not exists(select 1 from public.worker_roles where worker_id=v_worker and role_id=v_role and approved) then
    raise exception 'role not approved';
  end if;

  if exists (
    select 1 from public.shift_assignments a
    join public.shifts sh on sh.id=a.shift_id
    where a.worker_id=v_worker and a.cancelled_at is null and a.shift_id<>p_shift_id
      and sh.status<>'cancelled' and sh.starts_at<v_ends_at and sh.ends_at>v_starts_at
  ) then raise exception 'worker has overlapping shift'; end if;

  select count(*) into v_taken from public.shift_assignments where shift_id=p_shift_id and cancelled_at is null;
  if v_taken >= v_headcount then raise exception 'shift full'; end if;

  insert into public.shift_assignments(shift_id,worker_id,accepted_at)
  values(p_shift_id,v_worker,now())
  on conflict(shift_id,worker_id) do update set accepted_at=excluded.accepted_at,cancelled_at=null
  returning id into v_assignment;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_worker,'shift.accepted','shift_assignment',v_assignment,
    jsonb_build_object('shift_id',p_shift_id,'starts_at',v_starts_at,'ends_at',v_ends_at,
      'capacity',v_headcount,'active_assignments_before_accept',v_taken,
      'live_deployability_checked',true));
  return v_assignment;
end;
$$;

revoke all on function public.accept_shift(uuid) from public;
grant execute on function public.accept_shift(uuid) to authenticated;

comment on function public.worker_has_deployment_prerequisites(uuid) is
'Authoritative live readiness predicate: separate identity/residency/work eligibility, required consents, approved active role, non-blocking vetting, and current required training.';
comment on function public.worker_is_deployable(uuid) is
'Final deployability predicate. Requires Ops-managed status=deployable plus all live prerequisites.';
