-- QY Workforce: independent residency and work-eligibility evidence lifecycles.
-- Identity proof, residency and legal work eligibility are separate decisions.  This
-- migration keeps the profile columns as denormalised current-state summaries while
-- retaining purpose-specific evidence/audit records.  Production identity providers
-- remain disabled; only mock/staging/manual-review sources are accepted here.

create table public.residency_verifications (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  source text not null check (source in ('mock','singpass_myinfo','manual_document')),
  environment text not null check (environment in ('mock','staging')),
  status text not null check (status in ('passed','failed','manual_review')),
  residency_category text,
  evidence_hash text,
  checked_by uuid references public.profiles(id),
  checked_at timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  check (status <> 'passed' or nullif(trim(residency_category),'') is not null),
  check (valid_until is null or valid_until > checked_at)
);

create table public.work_eligibility_checks (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  source text not null check (source in ('mock','singpass_myinfo','manual_document','ops_review')),
  environment text not null check (environment in ('mock','staging')),
  outcome public.eligibility_status not null,
  evidence_hash text,
  checked_by uuid references public.profiles(id),
  checked_at timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  check (outcome <> 'unknown'),
  check (valid_until is null or valid_until > checked_at)
);

create index residency_verifications_worker_checked_idx
  on public.residency_verifications(worker_id, checked_at desc);
create index work_eligibility_checks_worker_checked_idx
  on public.work_eligibility_checks(worker_id, checked_at desc);

alter table public.residency_verifications enable row level security;
alter table public.work_eligibility_checks enable row level security;

create policy "workers read own residency verification" on public.residency_verifications
for select using (worker_id = auth.uid());
create policy "ops read residency verification" on public.residency_verifications
for select using (public.is_privileged());
create policy "workers read own work eligibility" on public.work_eligibility_checks
for select using (worker_id = auth.uid());
create policy "ops read work eligibility" on public.work_eligibility_checks
for select using (public.is_privileged());

-- Evidence rows are RPC-only.  Workers and ordinary authenticated clients cannot
-- forge verification outcomes by writing these tables directly.
revoke insert, update, delete on public.residency_verifications from authenticated;
revoke insert, update, delete on public.work_eligibility_checks from authenticated;

create or replace function public.record_residency_verification_staging(
  p_worker uuid,
  p_source text,
  p_environment text,
  p_status text,
  p_residency_category text default null,
  p_evidence_hash text default null,
  p_valid_until timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_category text := nullif(left(trim(coalesce(p_residency_category,'')),100),'');
  v_hash text := nullif(left(trim(coalesce(p_evidence_hash,'')),256),'');
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_source not in ('mock','singpass_myinfo','manual_document') then raise exception 'unsupported residency source'; end if;
  if p_environment not in ('mock','staging') then raise exception 'production verification disabled'; end if;
  if p_status not in ('passed','failed','manual_review') then raise exception 'invalid residency outcome'; end if;
  if p_status='passed' and v_category is null then raise exception 'residency category required'; end if;
  if p_valid_until is not null and p_valid_until <= now() then raise exception 'verification already expired'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=p_worker) then raise exception 'worker not found'; end if;

  insert into public.residency_verifications(
    worker_id,source,environment,status,residency_category,evidence_hash,checked_by,valid_until
  ) values (
    p_worker,p_source,p_environment,p_status,v_category,v_hash,auth.uid(),p_valid_until
  ) returning id into v_id;

  update public.worker_profiles
  set residency_verified=(p_status='passed'),
      residency_category=case when p_status='passed' then v_category else null end,
      updated_at=now()
  where user_id=p_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'residency_verification.recorded','residency_verification',v_id,
    jsonb_build_object('worker_id',p_worker,'source',p_source,'environment',p_environment,
                       'status',p_status,'valid_until',p_valid_until));
  return v_id;
end;
$$;

create or replace function public.record_work_eligibility_staging(
  p_worker uuid,
  p_source text,
  p_environment text,
  p_outcome public.eligibility_status,
  p_evidence_hash text default null,
  p_valid_until timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_hash text := nullif(left(trim(coalesce(p_evidence_hash,'')),256),'');
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_source not in ('mock','singpass_myinfo','manual_document','ops_review') then raise exception 'unsupported eligibility source'; end if;
  if p_environment not in ('mock','staging') then raise exception 'production verification disabled'; end if;
  if p_outcome is null or p_outcome='unknown' then raise exception 'conclusive or manual-review outcome required'; end if;
  if p_valid_until is not null and p_valid_until <= now() then raise exception 'eligibility check already expired'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=p_worker) then raise exception 'worker not found'; end if;

  insert into public.work_eligibility_checks(
    worker_id,source,environment,outcome,evidence_hash,checked_by,valid_until
  ) values (
    p_worker,p_source,p_environment,p_outcome,v_hash,auth.uid(),p_valid_until
  ) returning id into v_id;

  update public.worker_profiles
  set work_eligibility=p_outcome,
      eligibility_source=p_source,
      eligibility_checked_at=now(),
      updated_at=now()
  where user_id=p_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'work_eligibility.recorded','work_eligibility_check',v_id,
    jsonb_build_object('worker_id',p_worker,'source',p_source,'environment',p_environment,
                       'outcome',p_outcome,'valid_until',p_valid_until));
  return v_id;
end;
$$;

revoke all on function public.record_residency_verification_staging(uuid,text,text,text,text,text,timestamptz) from public;
revoke all on function public.record_work_eligibility_staging(uuid,text,text,public.eligibility_status,text,timestamptz) from public;
grant execute on function public.record_residency_verification_staging(uuid,text,text,text,text,text,timestamptz) to authenticated;
grant execute on function public.record_work_eligibility_staging(uuid,text,text,public.eligibility_status,text,timestamptz) to authenticated;

-- Compatibility boundary: the legacy identity-completion RPC may only complete
-- identity.  Call the two purpose-specific RPCs for residency / work eligibility.
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
  v_subject_hash text := nullif(left(trim(coalesce(p_provider_subject_hash,'')),256),'');
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_residency_verified or nullif(trim(coalesce(p_residency_category,'')),'') is not null
     or p_work_eligibility <> 'unknown' or nullif(trim(coalesce(p_eligibility_source,'')),'') is not null then
    raise exception 'residency and work eligibility must be recorded separately';
  end if;

  select worker_id,provider,environment into v_worker,v_provider,v_environment
  from public.identity_provider_sessions
  where id=p_session and status in ('initiated','callback_received') and expires_at>now()
  for update;
  if v_worker is null then raise exception 'identity session unavailable'; end if;
  if v_environment not in ('mock','staging') then raise exception 'production identity completion disabled'; end if;
  if v_subject_hash is null then raise exception 'provider subject hash required'; end if;

  update public.identity_provider_sessions
  set status='completed',provider_subject_hash=v_subject_hash,completed_at=now()
  where id=p_session;

  insert into public.identity_verifications(
    worker_id,provider,provider_subject_hash,status,verified_attributes,consent_recorded_at,verified_at
  ) values (
    v_worker,v_provider,v_subject_hash,
    case when p_identity_passed then 'passed' else 'failed' end,
    jsonb_build_object('identity_verified',p_identity_passed),
    now(),case when p_identity_passed then now() else null end
  );

  update public.worker_profiles
  set identity_verified=p_identity_passed,
      identity_provider=v_provider,
      identity_verified_at=case when p_identity_passed then now() else null end,
      updated_at=now()
  where user_id=v_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_verification.completed','worker_profile',v_worker,
    jsonb_build_object('provider',v_provider,'environment',v_environment,'identity_verified',p_identity_passed,
                       'separate_residency_and_eligibility',true));
end;
$$;

revoke all on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) from public;
grant execute on function public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text) to authenticated;

-- Gradual evidence migration: legacy workers remain deployable from profile summaries
-- until a purpose-specific evidence row exists.  Once evidence exists, its latest
-- non-expired outcome becomes authoritative for that purpose.
create or replace function public.worker_has_current_residency(p_worker_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((
    select wp.residency_verified and (
      not exists(select 1 from public.residency_verifications rv where rv.worker_id=wp.user_id)
      or exists(
        select 1 from public.residency_verifications rv
        where rv.id=(select rv2.id from public.residency_verifications rv2 where rv2.worker_id=wp.user_id order by rv2.checked_at desc,rv2.id desc limit 1)
          and rv.status='passed' and (rv.valid_until is null or rv.valid_until>now())
      )
    ) from public.worker_profiles wp where wp.user_id=p_worker_id
  ),false);
$$;

create or replace function public.worker_has_current_work_eligibility(p_worker_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((
    select wp.work_eligibility='eligible' and (
      not exists(select 1 from public.work_eligibility_checks we where we.worker_id=wp.user_id)
      or exists(
        select 1 from public.work_eligibility_checks we
        where we.id=(select we2.id from public.work_eligibility_checks we2 where we2.worker_id=wp.user_id order by we2.checked_at desc,we2.id desc limit 1)
          and we.outcome='eligible' and (we.valid_until is null or we.valid_until>now())
      )
    ) from public.worker_profiles wp where wp.user_id=p_worker_id
  ),false);
$$;

revoke all on function public.worker_has_current_residency(uuid) from public;
revoke all on function public.worker_has_current_work_eligibility(uuid) from public;

comment on table public.residency_verifications is 'Purpose-specific residency evidence; no raw Singpass/MyInfo payloads.';
comment on table public.work_eligibility_checks is 'Purpose-specific legal work-eligibility evidence; independent of identity and residency.';
comment on function public.record_residency_verification_staging(uuid,text,text,text,text,text,timestamptz) is 'Mock/staging/manual residency decision boundary. Production providers disabled.';
comment on function public.record_work_eligibility_staging(uuid,text,text,public.eligibility_status,text,timestamptz) is 'Mock/staging/manual work-eligibility decision boundary. Production providers disabled.';
