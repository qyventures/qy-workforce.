-- Keep the worker-facing readiness view aligned with the authoritative deployment
-- predicate, and keep the mock/staging identity flow to the minimum disclosure
-- contract. Identity, residency and work eligibility remain independently reviewed.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.identity_provider_sessions'::regclass
      and conname = 'identity_provider_sessions_minimum_scope_check'
  ) then
    alter table public.identity_provider_sessions
      add constraint identity_provider_sessions_minimum_scope_check
      check (requested_scopes = array['openid']::text[]) not valid;
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
  if p_requested_scopes is distinct from array['openid']::text[] then
    raise exception 'only the openid identity scope is permitted';
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
    array['openid']::text[],now()+interval '10 minutes'
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.started','identity_provider_session',v_id,
    jsonb_build_object('provider',p_provider,'environment',p_environment,'scope_contract','openid'));
  return v_id;
end;
$$;
revoke all on function public.start_identity_session(text,text,text,text,text[]) from public;
grant execute on function public.start_identity_session(text,text,text,text,text[]) to authenticated;

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
         consent_state.ok, public.worker_has_deployment_prerequisites(auth.uid())
  from me, role_count, skill_count, training_count, vetting_count, consent_state;
$$;
revoke all on function public.get_worker_readiness() from public;
grant execute on function public.get_worker_readiness() to authenticated;

comment on function public.get_worker_readiness() is
  'Worker-only, privacy-safe readiness summary. Deployable is calculated exclusively by the live deployment predicate; it is not a stored identity, residency or eligibility decision.';
comment on function public.start_identity_session(text,text,text,text,text[]) is
  'Starts a short-lived mock/staging identity session using only the fixed openid scope. Provider payloads, tokens and national identifiers remain outside the database.';
