-- QY Workforce: privacy-minimised mock/staging identity-session boundary.
-- This migration intentionally does not enable a production provider path.

-- Identity sessions contain only correlation hashes. Keep the database shape from
-- accepting blank values or impossible terminal timestamps even for privileged callers.
alter table public.identity_provider_sessions
  drop constraint if exists identity_provider_sessions_state_hash_check;
alter table public.identity_provider_sessions
  add constraint identity_provider_sessions_state_hash_check
  check (char_length(trim(state_hash)) between 32 and 256);

alter table public.identity_provider_sessions
  drop constraint if exists identity_provider_sessions_nonce_hash_check;
alter table public.identity_provider_sessions
  add constraint identity_provider_sessions_nonce_hash_check
  check (char_length(trim(nonce_hash)) between 32 and 256);

alter table public.identity_provider_sessions
  drop constraint if exists identity_provider_sessions_completion_check;
alter table public.identity_provider_sessions
  add constraint identity_provider_sessions_completion_check
  check (
    (status = 'completed' and completed_at is not null and provider_subject_hash is not null)
    or (status <> 'completed' and completed_at is null)
  ) not valid;

-- Clients may inspect their own session state through RLS, but state changes are
-- exclusively made by audited RPCs or the service-role callback worker.
revoke insert, update, delete on public.identity_provider_sessions from anon, authenticated;
revoke insert, update, delete on public.identity_verifications from anon, authenticated;

create or replace function public.start_identity_session(
  p_provider text default 'mock',
  p_environment text default 'mock',
  p_state_hash text default null,
  p_nonce_hash text default null,
  p_requested_scopes text[] default array['openid']::text[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_scopes text[];
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then
    raise exception 'worker profile required';
  end if;
  if p_provider not in ('mock','singpass_myinfo') then raise exception 'unsupported identity provider'; end if;
  if p_environment not in ('mock','staging') then raise exception 'production identity flow not enabled'; end if;
  if nullif(trim(p_state_hash),'') is null or char_length(trim(p_state_hash)) not between 32 and 256 then
    raise exception 'valid state hash required';
  end if;
  if nullif(trim(p_nonce_hash),'') is null or char_length(trim(p_nonce_hash)) not between 32 and 256 then
    raise exception 'valid nonce hash required';
  end if;

  -- This abstraction has no need to request raw MyInfo attributes. Restrict it
  -- to the OIDC correlation scope until a separately reviewed provider contract exists.
  select coalesce(array_agg(scope order by scope), '{}'::text[]) into v_scopes
  from (
    select distinct lower(trim(scope)) as scope
    from unnest(coalesce(p_requested_scopes, '{}'::text[])) as u(scope)
    where nullif(trim(scope),'') is not null
  ) requested;
  if coalesce(array_length(v_scopes,1),0) <> 1 or v_scopes[1] <> 'openid' then
    raise exception 'only the openid scope is permitted for mock/staging identity sessions';
  end if;
  if not exists(
    select 1 from public.worker_consents c
    where c.worker_id=auth.uid() and c.purpose='identity_verification'
      and c.granted=true and c.withdrawn_at is null
  ) then raise exception 'identity verification consent required'; end if;

  update public.identity_provider_sessions
     set status='expired'
   where worker_id=auth.uid() and provider=p_provider and environment=p_environment
     and status in ('initiated','callback_received') and expires_at<=now();

  if exists(
    select 1 from public.identity_provider_sessions
    where worker_id=auth.uid() and provider=p_provider and environment=p_environment
      and status in ('initiated','callback_received') and expires_at>now()
  ) then raise exception 'identity session already active'; end if;

  insert into public.identity_provider_sessions(
    worker_id,provider,environment,state_hash,nonce_hash,requested_scopes,expires_at
  ) values(
    auth.uid(),p_provider,p_environment,trim(p_state_hash),trim(p_nonce_hash),v_scopes,now()+interval '10 minutes'
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.started','identity_provider_session',v_id,
    jsonb_build_object('provider',p_provider,'environment',p_environment,'scope_count',1));
  return v_id;
end;
$$;

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
set search_path = public
as $$
declare
  v_worker uuid;
  v_provider text;
  v_environment text;
  v_subject_hash text := nullif(trim(p_provider_subject_hash),'');
  v_residency_category text := nullif(trim(p_residency_category),'');
  v_eligibility_source text := nullif(trim(p_eligibility_source),'');
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if v_subject_hash is null or char_length(v_subject_hash) not between 16 and 256 then
    raise exception 'valid provider subject hash required';
  end if;
  if v_residency_category is not null and char_length(v_residency_category)>80 then
    raise exception 'residency category too long';
  end if;
  if not p_residency_verified and v_residency_category is not null then
    raise exception 'residency category requires verified residency';
  end if;
  if v_eligibility_source is not null and char_length(v_eligibility_source)>160 then
    raise exception 'eligibility source too long';
  end if;

  select worker_id,provider,environment into v_worker,v_provider,v_environment
  from public.identity_provider_sessions
  where id=p_session and status='callback_received' and expires_at>now()
  for update;
  if v_worker is null then raise exception 'identity callback not available'; end if;
  if v_environment not in ('mock','staging') then raise exception 'production identity completion disabled'; end if;

  update public.identity_provider_sessions
     set status='completed', provider_subject_hash=v_subject_hash, completed_at=now()
   where id=p_session;

  insert into public.identity_verifications(worker_id,provider,provider_subject_hash,status,verified_attributes,consent_recorded_at,verified_at)
  values(
    v_worker,v_provider,v_subject_hash,
    case when p_identity_passed then 'passed' else 'failed' end,
    jsonb_build_object(
      'identity_verified',p_identity_passed,
      'residency_verified',coalesce(p_residency_verified,false),
      'residency_category',case when p_residency_verified then v_residency_category else null end,
      'work_eligibility',p_work_eligibility,
      'source',v_eligibility_source
    ), now(),case when p_identity_passed then now() else null end
  );

  update public.worker_profiles
  set identity_verified=p_identity_passed,
      identity_provider=v_provider,
      identity_verified_at=case when p_identity_passed then now() else null end,
      residency_category=case when p_residency_verified then v_residency_category else residency_category end,
      residency_verified=coalesce(p_residency_verified,false),
      work_eligibility=p_work_eligibility,
      eligibility_source=v_eligibility_source,
      eligibility_checked_at=case when p_work_eligibility<>'unknown' then now() else eligibility_checked_at end,
      updated_at=now()
  where user_id=v_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_verification.completed','worker_profile',v_worker,
    jsonb_build_object('provider',v_provider,'environment',v_environment,'identity_verified',p_identity_passed,
                       'residency_verified',p_residency_verified,'work_eligibility',p_work_eligibility));
end;
$$;

revoke all on function public.start_identity_session(text,text,text,text,text[]) from public;
grant execute on function public.start_identity_session(text,text,text,text,text[]) to authenticated;
revoke all on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) from public;
grant execute on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) to authenticated;

comment on function public.start_identity_session(text,text,text,text,text[]) is
'Worker-only mock/staging identity start. Only OIDC openid correlation scope is allowed; raw identity attributes are outside this database contract.';
comment on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) is
'Ops/Admin-only mock/staging completion after an audited callback state. Identity, residency and work eligibility are independently recorded.';
