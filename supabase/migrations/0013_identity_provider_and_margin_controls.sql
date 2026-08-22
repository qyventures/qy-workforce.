-- QY Workforce V1: staged identity provider abstraction, verification separation, margin reporting.

create table public.identity_provider_sessions (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  provider text not null check (provider in ('mock','singpass_myinfo')),
  environment text not null check (environment in ('mock','staging')),
  state_hash text not null,
  nonce_hash text not null,
  status text not null default 'initiated' check (status in ('initiated','callback_received','completed','failed','expired')),
  provider_subject_hash text,
  requested_scopes text[] not null default '{}',
  error_code text,
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(provider, environment, state_hash)
);

alter table public.identity_provider_sessions enable row level security;
create policy "workers read own identity sessions" on public.identity_provider_sessions
for select using (worker_id=auth.uid());
create policy "ops read identity sessions" on public.identity_provider_sessions
for select using (public.is_privileged());

-- Raw Singpass/MyInfo payloads must not be persisted here. Only normalized outcomes and hashes.
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
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then raise exception 'worker profile required'; end if;
  if p_provider not in ('mock','singpass_myinfo') then raise exception 'unsupported identity provider'; end if;
  if p_environment not in ('mock','staging') then raise exception 'production identity flow not enabled'; end if;
  if nullif(trim(p_state_hash),'') is null or nullif(trim(p_nonce_hash),'') is null then raise exception 'state and nonce hashes required'; end if;
  if not exists(
    select 1 from public.worker_consents c
    where c.worker_id=auth.uid() and c.purpose='identity_verification' and c.granted=true and c.withdrawn_at is null
  ) then raise exception 'identity verification consent required'; end if;

  insert into public.identity_provider_sessions(worker_id,provider,environment,state_hash,nonce_hash,requested_scopes,expires_at)
  values(auth.uid(),p_provider,p_environment,left(trim(p_state_hash),256),left(trim(p_nonce_hash),256),coalesce(p_requested_scopes,'{}'),now()+interval '10 minutes')
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.started','identity_provider_session',v_id,jsonb_build_object('provider',p_provider,'environment',p_environment));
  return v_id;
end;
$$;
revoke all on function public.start_identity_session(text,text,text,text,text[]) from public;
grant execute on function public.start_identity_session(text,text,text,text,text[]) to authenticated;

-- Service/ops boundary records normalized verification results. Identity, residency and work eligibility remain independent.
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
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  select worker_id,provider,environment into v_worker,v_provider,v_environment
  from public.identity_provider_sessions
  where id=p_session and status in ('initiated','callback_received') and expires_at>now()
  for update;
  if v_worker is null then raise exception 'identity session unavailable'; end if;
  if v_environment not in ('mock','staging') then raise exception 'production identity completion disabled'; end if;

  update public.identity_provider_sessions
  set status='completed',provider_subject_hash=left(trim(p_provider_subject_hash),256),completed_at=now()
  where id=p_session;

  insert into public.identity_verifications(worker_id,provider,provider_subject_hash,status,verified_attributes,consent_recorded_at,verified_at)
  values(
    v_worker,v_provider,left(trim(p_provider_subject_hash),256),
    case when p_identity_passed then 'passed' else 'failed' end,
    jsonb_build_object(
      'identity_verified',p_identity_passed,
      'residency_verified',coalesce(p_residency_verified,false),
      'residency_category',case when p_residency_verified then p_residency_category else null end,
      'work_eligibility',p_work_eligibility,
      'source',p_eligibility_source
    ),
    now(),case when p_identity_passed then now() else null end
  );

  update public.worker_profiles
  set identity_verified=p_identity_passed,
      identity_provider=v_provider,
      identity_verified_at=case when p_identity_passed then now() else null end,
      residency_category=case when p_residency_verified then p_residency_category else residency_category end,
      residency_verified=coalesce(p_residency_verified,false),
      work_eligibility=p_work_eligibility,
      eligibility_source=p_eligibility_source,
      eligibility_checked_at=case when p_work_eligibility<>'unknown' then now() else eligibility_checked_at end,
      updated_at=now()
  where user_id=v_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_verification.completed','worker_profile',v_worker,
    jsonb_build_object('provider',v_provider,'environment',v_environment,'identity_verified',p_identity_passed,
                       'residency_verified',p_residency_verified,'work_eligibility',p_work_eligibility));
end;
$$;
revoke all on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) from public;
grant execute on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) to authenticated;

-- Privileged margin RPC avoids exposing raw worker identity details to finance dashboards.
create or replace function public.get_site_margin_report(p_start date, p_end date)
returns table(
  site_id uuid,
  site_name text,
  client_id uuid,
  client_name text,
  shift_count bigint,
  approved_hours numeric,
  worker_cost numeric,
  client_revenue numeric,
  gross_margin numeric,
  gross_margin_pct numeric
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_app_role() not in ('ops_manager','finance','admin','auditor') then raise exception 'not authorised'; end if;
  if p_end<p_start then raise exception 'invalid period'; end if;

  return query
  select si.id,si.name,c.id,c.name,
         count(distinct sh.id),
         round(sum(t.payable_minutes)::numeric/60,2),
         round(sum(coalesce(t.worker_amount,0)),2),
         round(sum(coalesce(t.client_amount,0)),2),
         round(sum(coalesce(t.client_amount,0)-coalesce(t.worker_amount,0)),2),
         case when sum(coalesce(t.client_amount,0))>0 then
           round(100*sum(coalesce(t.client_amount,0)-coalesce(t.worker_amount,0))/sum(coalesce(t.client_amount,0)),2)
         else 0 end
  from public.timesheets t
  join public.shift_assignments sa on sa.id=t.assignment_id
  join public.shifts sh on sh.id=sa.shift_id
  join public.sites si on si.id=sh.site_id
  join public.clients c on c.id=si.client_id
  where t.status in ('approved','payroll_ready') and sh.starts_at::date between p_start and p_end
  group by si.id,si.name,c.id,c.name
  order by c.name,si.name;
end;
$$;
revoke all on function public.get_site_margin_report(date,date) from public;
grant execute on function public.get_site_margin_report(date,date) to authenticated;
