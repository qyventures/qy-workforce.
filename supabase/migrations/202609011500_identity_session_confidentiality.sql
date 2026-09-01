-- Identity-session secrets and correlation references must never be returned to worker clients.
-- Mock is the only local provider; Singpass/MyInfo is exposed only through the staging abstraction.

revoke select on table public.identity_provider_sessions from public, anon, authenticated;

-- Validate all new writes without failing deployment because of an old, invalid staging row.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.identity_provider_sessions'::regclass
      and conname='identity_provider_sessions_provider_environment_check'
  ) then
    alter table public.identity_provider_sessions
      add constraint identity_provider_sessions_provider_environment_check
      check (
        (provider='mock' and environment='mock')
        or (provider='singpass_myinfo' and environment='staging')
      ) not valid;
  end if;
end;
$$;

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
set search_path=public
as $$
declare
  v_id uuid;
begin
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then
    raise exception 'worker profile required';
  end if;
  if p_provider is null or p_environment is null
     or (p_provider = 'mock' and p_environment <> 'mock')
     or (p_provider = 'singpass_myinfo' and p_environment <> 'staging')
     or p_provider not in ('mock','singpass_myinfo') then
    raise exception 'invalid provider environment';
  end if;
  if nullif(trim(p_state_hash),'') is null or length(trim(p_state_hash)) < 32 then
    raise exception 'valid state hash required';
  end if;
  if nullif(trim(p_nonce_hash),'') is null or length(trim(p_nonce_hash)) < 32 then
    raise exception 'valid nonce hash required';
  end if;
  if coalesce(array_length(p_requested_scopes,1),0) > 12 then
    raise exception 'too many requested scopes';
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
    auth.uid(),p_provider,p_environment,left(trim(p_state_hash),256),left(trim(p_nonce_hash),256),
    coalesce(p_requested_scopes,'{}'),now()+interval '10 minutes'
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.started','identity_provider_session',v_id,
    jsonb_build_object('provider',p_provider,'environment',p_environment));
  return v_id;
end;
$$;
revoke all on function public.start_identity_session(text,text,text,text,text[]) from public;
grant execute on function public.start_identity_session(text,text,text,text,text[]) to authenticated;

-- This worker-facing read model deliberately excludes state, nonce and provider-subject hashes.
create or replace function public.get_own_identity_session_status()
returns table(
  id uuid,
  provider text,
  environment text,
  status text,
  error_code text,
  expires_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path=public
as $$
  select ips.id, ips.provider, ips.environment, ips.status, ips.error_code,
         ips.expires_at, ips.completed_at, ips.created_at
  from public.identity_provider_sessions ips
  where ips.worker_id=auth.uid()
  order by ips.created_at desc
  limit 50;
$$;
revoke all on function public.get_own_identity_session_status() from public;
grant execute on function public.get_own_identity_session_status() to authenticated;

-- Do not complete an old session whose provider/environment combination is no longer allowed.
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
  if (v_provider = 'mock' and v_environment <> 'mock')
     or (v_provider = 'singpass_myinfo' and v_environment <> 'staging') then
    raise exception 'invalid provider environment';
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
