-- QY Workforce: close the onboarding-to-qualification review gap.
-- Role approvals must originate from a worker-declared interest. Training outcomes
-- are server-calculated, audited and protected by separation of duties.

create or replace function public.review_worker_role(
  p_worker_id uuid,
  p_role_id uuid,
  p_approved boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_existing boolean;
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_worker_id is null or p_role_id is null then raise exception 'worker and role required'; end if;
  if p_worker_id = v_actor then raise exception 'self-review not permitted'; end if;
  if not exists (select 1 from public.worker_profiles where user_id = p_worker_id) then
    raise exception 'worker not found';
  end if;
  if not exists (select 1 from public.roles where id = p_role_id and active) then
    raise exception 'active role not found';
  end if;
  perform 1
  from public.worker_role_interests
  where worker_id = p_worker_id and role_id = p_role_id
  for update;
  if not found then
    raise exception 'worker role interest not found';
  end if;
  if not p_approved and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'reason required when declining role';
  end if;

  select approved
    into v_existing
  from public.worker_roles
  where worker_id = p_worker_id and role_id = p_role_id
  for update;

  if p_approved then
    insert into public.worker_roles(worker_id, role_id, approved, approved_at, approved_by)
    values (p_worker_id, p_role_id, true, now(), v_actor)
    on conflict (worker_id, role_id) do update
      set approved = true,
          approved_at = excluded.approved_at,
          approved_by = excluded.approved_by;
  elsif found then
    update public.worker_roles
       set approved = false,
           approved_at = null,
           approved_by = null
     where worker_id = p_worker_id and role_id = p_role_id;
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    v_actor,
    case when p_approved then 'worker_role.approved' else 'worker_role.declined' end,
    'worker_profile',
    p_worker_id,
    jsonb_build_object(
      'role_id', p_role_id,
      'previous_approved', coalesce(v_existing, false),
      'interest_verified', true,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );
end;
$$;

revoke all on function public.review_worker_role(uuid,uuid,boolean,text) from public;
grant execute on function public.review_worker_role(uuid,uuid,boolean,text) to authenticated;

create or replace function public.review_worker_training(
  p_training_id uuid,
  p_outcome public.training_status,
  p_evidence_ref text default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_worker uuid;
  v_old public.training_status;
  v_validity_days integer;
  v_evidence text := nullif(trim(coalesce(p_evidence_ref, '')), '');
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_outcome not in ('passed', 'failed') then raise exception 'invalid training review outcome'; end if;
  if p_outcome = 'passed' and v_evidence is null then raise exception 'evidence reference required'; end if;
  if p_outcome = 'failed' and v_reason is null then raise exception 'reason required when failing training'; end if;
  if v_evidence is not null and char_length(v_evidence) > 500 then raise exception 'evidence reference too long'; end if;
  if v_reason is not null and char_length(v_reason) > 500 then raise exception 'reason too long'; end if;

  select wt.worker_id, wt.status, tm.validity_days
    into v_worker, v_old, v_validity_days
  from public.worker_training wt
  join public.training_modules tm on tm.id = wt.module_id
  where wt.id = p_training_id and tm.active
  for update of wt;

  if not found then raise exception 'active training assignment not found'; end if;
  if v_worker = v_actor then raise exception 'self-review not permitted'; end if;

  update public.worker_training
     set status = p_outcome,
         completed_at = now(),
         expires_at = case
           when p_outcome = 'passed' and v_validity_days is not null
             then now() + make_interval(days => v_validity_days)
           else null
         end,
         evidence_ref = case when p_outcome = 'passed' then v_evidence else null end,
         verified_by = v_actor
   where id = p_training_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    v_actor,
    'worker_training.reviewed',
    'worker_profile',
    v_worker,
    jsonb_build_object(
      'training_id', p_training_id,
      'from_status', v_old,
      'to_status', p_outcome,
      'evidence_present', v_evidence is not null,
      'reason', v_reason,
      'validity_days', v_validity_days
    )
  );
end;
$$;

revoke all on function public.review_worker_training(uuid,public.training_status,text,text) from public;
grant execute on function public.review_worker_training(uuid,public.training_status,text,text) to authenticated;

create or replace function public.get_worker_review_queue(p_limit integer default 100)
returns table (
  worker_id uuid,
  worker_alias text,
  worker_status public.worker_status,
  identity_verified boolean,
  residency_verified boolean,
  work_eligibility public.eligibility_status,
  approved_roles integer,
  pending_roles integer,
  outstanding_training integer,
  open_vetting integer,
  deployable_now boolean,
  updated_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;

  return query
  select
    wp.user_id,
    'W-' || upper(substr(replace(wp.user_id::text, '-', ''), 1, 8)),
    wp.status,
    wp.identity_verified,
    wp.residency_verified,
    wp.work_eligibility,
    (select count(*)::integer from public.worker_roles wr where wr.worker_id = wp.user_id and wr.approved),
    (select count(*)::integer
       from public.worker_role_interests wri
      where wri.worker_id = wp.user_id
        and not exists (
          select 1 from public.worker_roles wr
          where wr.worker_id = wri.worker_id and wr.role_id = wri.role_id and wr.approved
        )),
    (select count(*)::integer
       from public.training_modules tm
      where tm.active
        and (tm.role_id is null or exists (
          select 1 from public.worker_roles wr
          where wr.worker_id = wp.user_id and wr.role_id = tm.role_id and wr.approved
        ))
        and not exists (
          select 1 from public.worker_training wt
          where wt.worker_id = wp.user_id and wt.module_id = tm.id
            and wt.status = 'passed'
            and (wt.expires_at is null or wt.expires_at > now())
        )),
    (select count(*)::integer from public.worker_vetting wv
      where wv.worker_id = wp.user_id and wv.status in ('pending', 'manual_review', 'failed')),
    public.worker_is_deployable(wp.user_id),
    wp.updated_at
  from public.worker_profiles wp
  order by
    case when wp.status in ('suspended', 'rejected') then 2 else 0 end,
    case when public.worker_is_deployable(wp.user_id) then 1 else 0 end,
    wp.updated_at asc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

revoke all on function public.get_worker_review_queue(integer) from public;
grant execute on function public.get_worker_review_queue(integer) to authenticated;

-- Direct qualification writes are no longer an authenticated-client capability.
drop policy if exists "ops manage training" on public.worker_training;
revoke insert, update, delete on public.worker_training from authenticated;

create index if not exists idx_worker_vetting_blocking_lookup
  on public.worker_vetting(worker_id, status)
  where status in ('pending', 'failed', 'manual_review');

comment on function public.review_worker_training(uuid,public.training_status,text,text) is
'Ops-only training review with row locking, separation of duties, server-calculated expiry and audit evidence.';
