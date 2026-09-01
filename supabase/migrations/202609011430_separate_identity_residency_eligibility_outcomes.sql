-- Keep identity, residency and work eligibility as independently asserted outcomes.
-- The legacy completion signature remains stable, but non-identity inputs are rejected.

create or replace function public.complete_identity_verification_staging(
  p_session uuid,
  p_provider_subject_hash text,
  p_identity_passed boolean,
  p_residency_category text default null,
  p_residency_verified boolean default false,
  p_work_eligibility public.eligibility_status default 'unknown',
  p_eligibility_source text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_worker uuid;
  v_provider text;
  v_environment text;
  v_subject_hash text := trim(p_provider_subject_hash);
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_identity_passed is null then raise exception 'identity outcome required'; end if;
  if coalesce(p_residency_verified, false)
     or nullif(trim(p_residency_category), '') is not null
     or p_work_eligibility <> 'unknown'
     or nullif(trim(p_eligibility_source), '') is not null then
    raise exception 'residency and work eligibility require separate verification';
  end if;
  if v_subject_hash is null
     or length(v_subject_hash) not between 32 and 256
     or v_subject_hash !~ '^[0-9A-Fa-f]+$' then
    raise exception 'valid provider subject hash required';
  end if;

  select worker_id, provider, environment
    into v_worker, v_provider, v_environment
  from public.identity_provider_sessions
  where id=p_session and status='callback_received' and expires_at>now()
  for update;
  if v_worker is null then raise exception 'identity session unavailable'; end if;
  if v_environment not in ('mock','staging') then
    raise exception 'production identity completion disabled';
  end if;

  update public.identity_provider_sessions
  set status='completed', provider_subject_hash=lower(v_subject_hash), completed_at=now()
  where id=p_session;

  insert into public.identity_verifications(
    worker_id, provider, provider_subject_hash, status, verified_attributes,
    consent_recorded_at, verified_at
  ) values (
    v_worker, v_provider, lower(v_subject_hash),
    case when p_identity_passed then 'passed' else 'failed' end,
    jsonb_build_object('identity_verified', p_identity_passed),
    now(), case when p_identity_passed then now() else null end
  );

  update public.worker_profiles
  set identity_verified=p_identity_passed,
      identity_provider=v_provider,
      identity_verified_at=case when p_identity_passed then now() else null end,
      updated_at=now()
  where user_id=v_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_verification.completed','worker_profile',v_worker,
    jsonb_build_object('provider',v_provider,'environment',v_environment,
                       'identity_verified',p_identity_passed));
end;
$$;
revoke all on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) from public;
grant execute on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) to authenticated;

create or replace function public.record_residency_verification_staging(
  p_worker uuid,
  p_verified boolean,
  p_category text default null,
  p_source text default 'manual_review'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_category text := nullif(trim(p_category), '');
  v_source text := nullif(trim(p_source), '');
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_verified is null then raise exception 'residency outcome required'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=p_worker) then
    raise exception 'worker profile required';
  end if;
  if p_verified and v_category is null then raise exception 'residency category required'; end if;
  if v_source is null or length(v_source) > 100 then raise exception 'valid residency source required'; end if;

  update public.worker_profiles
  set residency_verified=p_verified,
      residency_category=case when p_verified then left(v_category,100) else null end,
      updated_at=now()
  where user_id=p_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'residency_verification.recorded','worker_profile',p_worker,
    jsonb_build_object('verified',p_verified,'category',case when p_verified then left(v_category,100) else null end,
                       'source',v_source));
end;
$$;
revoke all on function public.record_residency_verification_staging(uuid,boolean,text,text) from public;
grant execute on function public.record_residency_verification_staging(uuid,boolean,text,text) to authenticated;

create or replace function public.record_work_eligibility_staging(
  p_worker uuid,
  p_status public.eligibility_status,
  p_source text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_source text := nullif(trim(p_source), '');
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=p_worker) then
    raise exception 'worker profile required';
  end if;
  if p_status is null then raise exception 'eligibility status required'; end if;
  if v_source is null or length(v_source) > 100 then raise exception 'valid eligibility source required'; end if;
  if not exists(
    select 1 from public.worker_consents
    where worker_id=p_worker and purpose='work_eligibility'
      and granted and withdrawn_at is null
  ) then raise exception 'work eligibility consent required'; end if;

  update public.worker_profiles
  set work_eligibility=p_status,
      eligibility_source=left(v_source,100),
      eligibility_checked_at=now(),
      updated_at=now()
  where user_id=p_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'work_eligibility.recorded','worker_profile',p_worker,
    jsonb_build_object('status',p_status,'source',v_source));
end;
$$;
revoke all on function public.record_work_eligibility_staging(uuid,public.eligibility_status,text) from public;
grant execute on function public.record_work_eligibility_staging(uuid,public.eligibility_status,text) to authenticated;
