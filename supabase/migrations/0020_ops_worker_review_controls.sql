-- QY Workforce: audited Ops worker-review controls.
-- Keeps worker readiness decisions server-authoritative and avoids broad client-side
-- mutation of worker_profiles, worker_roles and worker_vetting.

-- Ops/Admin review queue: intentionally pseudonymous and limited to operational fields.
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
  if not public.is_ops() then
    raise exception 'not authorised';
  end if;

  return query
  select
    wp.user_id,
    'W-' || upper(substr(replace(wp.user_id::text,'-',''),1,8)) as worker_alias,
    wp.status,
    wp.identity_verified,
    wp.residency_verified,
    wp.work_eligibility,
    (select count(*)::integer from public.worker_roles wr where wr.worker_id=wp.user_id and wr.approved),
    (select count(*)::integer from public.worker_roles wr where wr.worker_id=wp.user_id and not wr.approved),
    (select count(*)::integer
       from public.training_modules tm
      where tm.active
        and (tm.role_id is null or exists (
          select 1 from public.worker_roles wr
          where wr.worker_id=wp.user_id and wr.role_id=tm.role_id and wr.approved
        ))
        and not exists (
          select 1 from public.worker_training wt
          where wt.worker_id=wp.user_id and wt.module_id=tm.id
            and wt.status='passed'
            and (wt.expires_at is null or wt.expires_at > now())
        )),
    (select count(*)::integer from public.worker_vetting wv
      where wv.worker_id=wp.user_id and wv.status in ('pending','manual_review','failed')),
    public.worker_is_deployable(wp.user_id),
    wp.updated_at
  from public.worker_profiles wp
  order by
    case when wp.status in ('suspended','rejected') then 2 else 0 end,
    case when public.worker_is_deployable(wp.user_id) then 1 else 0 end,
    wp.updated_at asc
  limit greatest(1, least(coalesce(p_limit,100),500));
end;
$$;

revoke all on function public.get_worker_review_queue(integer) from public;
grant execute on function public.get_worker_review_queue(integer) to authenticated;

-- Role-interest approval/revocation. The row is locked so concurrent reviewers cannot
-- produce contradictory approvals. Self-review is prohibited if the target is also staff.
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
  if not exists(select 1 from public.worker_profiles where user_id=p_worker_id) then raise exception 'worker not found'; end if;
  if not exists(select 1 from public.roles where id=p_role_id and active) then raise exception 'active role not found'; end if;
  if p_approved = false and nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'reason required when declining role'; end if;

  select approved into v_existing
  from public.worker_roles
  where worker_id=p_worker_id and role_id=p_role_id
  for update;
  if not found then raise exception 'worker role interest not found'; end if;

  update public.worker_roles
     set approved=p_approved,
         approved_at=case when p_approved then now() else null end,
         approved_by=case when p_approved then v_actor else null end
   where worker_id=p_worker_id and role_id=p_role_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_actor,
         case when p_approved then 'worker_role.approved' else 'worker_role.declined' end,
         'worker_profile',p_worker_id,
         jsonb_build_object('role_id',p_role_id,'previous_approved',v_existing,'reason',nullif(trim(coalesce(p_reason,'')),'')));
end;
$$;

revoke all on function public.review_worker_role(uuid,uuid,boolean,text) from public;
grant execute on function public.review_worker_role(uuid,uuid,boolean,text) to authenticated;

-- Vetting outcome decision. Notes are explicitly redacted/operational, not raw documents.
create or replace function public.review_worker_vetting(
  p_vetting_id uuid,
  p_status public.verification_stage,
  p_notes_redacted text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_worker uuid;
  v_old public.verification_stage;
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_status not in ('passed','failed','manual_review') then raise exception 'invalid review status'; end if;
  if p_status in ('failed','manual_review') and nullif(trim(coalesce(p_notes_redacted,'')),'') is null then
    raise exception 'redacted review note required';
  end if;

  select worker_id,status into v_worker,v_old
  from public.worker_vetting where id=p_vetting_id for update;
  if not found then raise exception 'vetting record not found'; end if;
  if v_worker = v_actor then raise exception 'self-review not permitted'; end if;

  update public.worker_vetting
     set status=p_status,
         reviewed_by=v_actor,
         reviewed_at=now(),
         notes_redacted=nullif(trim(coalesce(p_notes_redacted,'')),'')
   where id=p_vetting_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_actor,'worker_vetting.reviewed','worker_profile',v_worker,
         jsonb_build_object('vetting_id',p_vetting_id,'from_status',v_old,'to_status',p_status,'note_present',nullif(trim(coalesce(p_notes_redacted,'')),'') is not null));
end;
$$;

revoke all on function public.review_worker_vetting(uuid,public.verification_stage,text) from public;
grant execute on function public.review_worker_vetting(uuid,public.verification_stage,text) to authenticated;

-- Final operational status gate. Deployable cannot be set unless every live prerequisite
-- except the stored final status itself is currently satisfied.
create or replace function public.set_worker_operational_status(
  p_worker_id uuid,
  p_status public.worker_status,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.worker_status;
  v_prereq boolean;
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_worker_id is null then raise exception 'worker required'; end if;
  if p_worker_id = v_actor then raise exception 'self-review not permitted'; end if;

  select status into v_old from public.worker_profiles where user_id=p_worker_id for update;
  if not found then raise exception 'worker not found'; end if;

  if p_status in ('suspended','rejected') and nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'reason required for suspended/rejected status';
  end if;

  if p_status = 'deployable' then
    select public.worker_has_deployment_prerequisites(p_worker_id) into v_prereq;
    if not coalesce(v_prereq,false) then raise exception 'worker deployment prerequisites incomplete'; end if;
  end if;

  update public.worker_profiles set status=p_status, updated_at=now() where user_id=p_worker_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_actor,'worker_status.changed','worker_profile',p_worker_id,
         jsonb_build_object('from_status',v_old,'to_status',p_status,'reason',nullif(trim(coalesce(p_reason,'')),'')));
end;
$$;

revoke all on function public.set_worker_operational_status(uuid,public.worker_status,text) from public;
grant execute on function public.set_worker_operational_status(uuid,public.worker_status,text) to authenticated;

-- Force privileged client mutations through the audited RPC boundary. SECURITY DEFINER
-- functions above retain required access while normal authenticated clients do not.
revoke update on public.worker_profiles from authenticated;
revoke insert, update, delete on public.worker_roles from authenticated;
revoke insert, update, delete on public.worker_vetting from authenticated;
