-- QY Workforce: keep identity, residency and work eligibility as separate,
-- internally consistent facts. NOT VALID preserves compatibility with any
-- pre-existing staging rows while enforcing all future writes/updates.

alter table public.worker_profiles
  drop constraint if exists worker_profiles_identity_timestamp_consistency;
alter table public.worker_profiles
  add constraint worker_profiles_identity_timestamp_consistency
  check ((identity_verified and identity_verified_at is not null)
      or (not identity_verified and identity_verified_at is null)) not valid;

alter table public.worker_profiles
  drop constraint if exists worker_profiles_residency_category_consistency;
alter table public.worker_profiles
  add constraint worker_profiles_residency_category_consistency
  check ((residency_verified and nullif(trim(residency_category), '') is not null)
      or (not residency_verified and residency_category is null)) not valid;

alter table public.worker_profiles
  drop constraint if exists worker_profiles_eligibility_evidence_consistency;
alter table public.worker_profiles
  add constraint worker_profiles_eligibility_evidence_consistency
  check ((work_eligibility = 'unknown' and eligibility_checked_at is null)
      or (work_eligibility <> 'unknown' and eligibility_checked_at is not null)) not valid;

-- A later unknown result must not leave older evidence that could be mistaken
-- for a current eligibility decision.
create or replace function public.complete_identity_verification_staging(
  p_session uuid, p_provider_subject_hash text, p_identity_passed boolean,
  p_residency_category text default null, p_residency_verified boolean default false,
  p_work_eligibility public.eligibility_status default 'unknown',
  p_eligibility_source text default null
)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_worker uuid; v_provider text; v_environment text;
  v_subject_hash text := nullif(trim(p_provider_subject_hash),'');
  v_residency_category text := nullif(trim(p_residency_category),'');
  v_eligibility_source text := nullif(trim(p_eligibility_source),'');
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if v_subject_hash is null or char_length(v_subject_hash) not between 16 and 256 then raise exception 'valid provider subject hash required'; end if;
  if v_residency_category is not null and char_length(v_residency_category)>80 then raise exception 'residency category too long'; end if;
  if p_residency_verified and v_residency_category is null then raise exception 'verified residency category required'; end if;
  if not p_residency_verified and v_residency_category is not null then raise exception 'residency category requires verified residency'; end if;
  if v_eligibility_source is not null and char_length(v_eligibility_source)>160 then raise exception 'eligibility source too long'; end if;
  if p_work_eligibility = 'unknown' and v_eligibility_source is not null then raise exception 'eligibility source requires a determinate eligibility result'; end if;

  select worker_id,provider,environment into v_worker,v_provider,v_environment
  from public.identity_provider_sessions
  where id=p_session and status='callback_received' and expires_at>now() for update;
  if v_worker is null then raise exception 'identity callback not available'; end if;
  if v_environment not in ('mock','staging') then raise exception 'production identity completion disabled'; end if;

  update public.identity_provider_sessions set status='completed', provider_subject_hash=v_subject_hash, completed_at=now() where id=p_session;
  insert into public.identity_verifications(worker_id,provider,provider_subject_hash,status,verified_attributes,consent_recorded_at,verified_at)
  values(v_worker,v_provider,v_subject_hash,case when p_identity_passed then 'passed' else 'failed' end,
    jsonb_build_object('identity_verified',p_identity_passed,'residency_verified',coalesce(p_residency_verified,false),
      'residency_category',case when p_residency_verified then v_residency_category else null end,
      'work_eligibility',p_work_eligibility,'source',v_eligibility_source), now(),case when p_identity_passed then now() else null end);

  update public.worker_profiles set
    identity_verified=p_identity_passed, identity_provider=v_provider,
    identity_verified_at=case when p_identity_passed then now() else null end,
    residency_category=case when p_residency_verified then v_residency_category else null end,
    residency_verified=coalesce(p_residency_verified,false), work_eligibility=p_work_eligibility,
    eligibility_source=case when p_work_eligibility <> 'unknown' then v_eligibility_source else null end,
    eligibility_checked_at=case when p_work_eligibility <> 'unknown' then now() else null end,
    updated_at=now() where user_id=v_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_verification.completed','worker_profile',v_worker,
    jsonb_build_object('provider',v_provider,'environment',v_environment,'identity_verified',p_identity_passed,
      'residency_verified',p_residency_verified,'work_eligibility',p_work_eligibility));
end;
$$;

revoke all on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) from public;
grant execute on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) to authenticated;
