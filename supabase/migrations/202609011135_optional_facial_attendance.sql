-- Optional enhanced attendance verification for QY Workforce.
-- Default remains authenticated worker + server-authoritative GPS/geofence.
-- Facial verification is 1:1 only, consent-bound, provider-validated, and never stores raw images/templates here.

alter table public.sites
  add column if not exists attendance_security_level text not null default 'gps_only';

alter table public.sites drop constraint if exists sites_attendance_security_level_check;
alter table public.sites add constraint sites_attendance_security_level_check
  check (attendance_security_level in ('gps_only','facial_optional','facial_required'));

create table if not exists public.attendance_biometric_consents (
  worker_id uuid primary key references public.profiles(id),
  status text not null check (status in ('opted_in','opted_out')),
  consent_version text,
  consent_source text,
  consented_at timestamptz,
  opted_out_at timestamptz,
  updated_at timestamptz not null default now(),
  check (consent_version is null or char_length(consent_version) <= 80),
  check (consent_source is null or char_length(consent_source) <= 160),
  check ((status='opted_in' and consented_at is not null and opted_out_at is null)
      or (status='opted_out' and opted_out_at is not null))
);

create table if not exists public.attendance_verification_evidence (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.shift_assignments(id),
  worker_id uuid not null references public.profiles(id),
  event_type text not null check (event_type in ('clock_in','clock_out')),
  verification_method text not null check (verification_method in ('selfie_liveness_1to1','manual_fallback')),
  result text not null check (result in ('passed','failed')),
  provider_attempt_hash text,
  liveness_passed boolean,
  match_passed boolean,
  override_reason text,
  verified_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  recorded_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (provider_attempt_hash is null or char_length(provider_attempt_hash) <= 128),
  check (override_reason is null or char_length(trim(override_reason)) between 1 and 500),
  check (expires_at > verified_at),
  check (
    (verification_method='selfie_liveness_1to1' and provider_attempt_hash is not null and liveness_passed is not null and match_passed is not null and override_reason is null)
    or
    (verification_method='manual_fallback' and override_reason is not null and provider_attempt_hash is null)
  )
);

create index if not exists attendance_verification_assignment_idx
  on public.attendance_verification_evidence(assignment_id,event_type,verified_at desc);
create index if not exists attendance_verification_unused_idx
  on public.attendance_verification_evidence(assignment_id,event_type,expires_at)
  where used_at is null and result='passed';

alter table public.attendance_biometric_consents enable row level security;
alter table public.attendance_verification_evidence enable row level security;

revoke insert,update,delete on public.attendance_biometric_consents from anon,authenticated;
revoke insert,update,delete on public.attendance_verification_evidence from anon,authenticated;

create policy "workers read own attendance biometric consent" on public.attendance_biometric_consents
  for select using (worker_id=auth.uid());
create policy "privileged read attendance biometric consent" on public.attendance_biometric_consents
  for select using (public.is_privileged());
create policy "workers read own attendance verification evidence" on public.attendance_verification_evidence
  for select using (worker_id=auth.uid());
create policy "privileged read attendance verification evidence" on public.attendance_verification_evidence
  for select using (public.is_privileged());

create or replace function public.set_attendance_biometric_consent(
  p_status text,
  p_consent_version text default null,
  p_consent_source text default 'worker_app',
  p_effective_at timestamptz default now()
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_status not in ('opted_in','opted_out') then raise exception 'invalid consent status'; end if;
  if p_effective_at is null or p_effective_at > now()+interval '5 minutes' then raise exception 'invalid effective time'; end if;
  if p_consent_version is not null and char_length(p_consent_version)>80 then raise exception 'consent version too long'; end if;
  if p_consent_source is not null and char_length(p_consent_source)>160 then raise exception 'consent source too long'; end if;

  insert into public.attendance_biometric_consents(worker_id,status,consent_version,consent_source,consented_at,opted_out_at,updated_at)
  values(
    auth.uid(),p_status,nullif(trim(p_consent_version),''),nullif(trim(p_consent_source),''),
    case when p_status='opted_in' then p_effective_at else null end,
    case when p_status='opted_out' then p_effective_at else null end,
    now()
  )
  on conflict(worker_id) do update set
    status=excluded.status,
    consent_version=case when excluded.status='opted_in' then excluded.consent_version else attendance_biometric_consents.consent_version end,
    consent_source=case when excluded.status='opted_in' then excluded.consent_source else attendance_biometric_consents.consent_source end,
    consented_at=case when excluded.status='opted_in' then excluded.consented_at else attendance_biometric_consents.consented_at end,
    opted_out_at=excluded.opted_out_at,
    updated_at=now();

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.biometric_consent_changed','worker',auth.uid(),jsonb_build_object('status',p_status));
end $$;

revoke all on function public.set_attendance_biometric_consent(text,text,text,timestamptz) from public;
grant execute on function public.set_attendance_biometric_consent(text,text,text,timestamptz) to authenticated;

create or replace function public.configure_site_attendance_security(
  p_site_id uuid,
  p_level text
) returns void
language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select public.current_app_role() into v_role;
  if v_role not in ('ops_manager','admin') then raise exception 'not authorised'; end if;
  if p_level not in ('gps_only','facial_optional','facial_required') then raise exception 'invalid attendance security level'; end if;
  update public.sites set attendance_security_level=p_level where id=p_site_id;
  if not found then raise exception 'site not found'; end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.site_security_changed','site',p_site_id,jsonb_build_object('level',p_level));
end $$;

revoke all on function public.configure_site_attendance_security(uuid,text) from public;
grant execute on function public.configure_site_attendance_security(uuid,text) to authenticated;

-- Backend/provider callback only. The client must never be able to assert a biometric match.
-- No raw selfie or facial template is persisted; only an opaque hashed provider attempt reference.
create or replace function public.record_attendance_biometric_result(
  p_assignment_id uuid,
  p_worker_id uuid,
  p_event_type text,
  p_result text,
  p_provider_attempt_hash text,
  p_liveness_passed boolean,
  p_match_passed boolean,
  p_verified_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_assignment_worker uuid; v_consent text;
begin
  if p_event_type not in ('clock_in','clock_out') then raise exception 'invalid event type'; end if;
  if p_result not in ('passed','failed') then raise exception 'invalid result'; end if;
  if p_provider_attempt_hash is null or char_length(trim(p_provider_attempt_hash)) not between 16 and 128 then raise exception 'invalid provider attempt reference'; end if;
  if p_verified_at is null or p_verified_at > now()+interval '5 minutes' or p_verified_at < now()-interval '15 minutes' then raise exception 'invalid verification time'; end if;
  select worker_id into v_assignment_worker from public.shift_assignments where id=p_assignment_id and cancelled_at is null and accepted_at is not null;
  if v_assignment_worker is null or v_assignment_worker<>p_worker_id then raise exception 'assignment worker mismatch'; end if;
  select status into v_consent from public.attendance_biometric_consents where worker_id=p_worker_id;
  if coalesce(v_consent,'opted_out')<>'opted_in' then raise exception 'active biometric consent required'; end if;
  if p_result='passed' and (p_liveness_passed is distinct from true or p_match_passed is distinct from true) then raise exception 'passed verification requires liveness and 1:1 match'; end if;

  insert into public.attendance_verification_evidence(
    assignment_id,worker_id,event_type,verification_method,result,provider_attempt_hash,liveness_passed,match_passed,verified_at,expires_at,recorded_by
  ) values(
    p_assignment_id,p_worker_id,p_event_type,'selfie_liveness_1to1',p_result,trim(p_provider_attempt_hash),p_liveness_passed,p_match_passed,p_verified_at,p_verified_at+interval '10 minutes',null
  ) returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(null,'attendance.biometric_result_recorded','attendance_verification',v_id,
    jsonb_build_object('assignment_id',p_assignment_id,'event_type',p_event_type,'result',p_result));
  return v_id;
end $$;

revoke all on function public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamptz) from public;
revoke all on function public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamptz) from anon,authenticated;
grant execute on function public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamptz) to service_role;

create or replace function public.create_attendance_manual_fallback(
  p_assignment_id uuid,
  p_event_type text,
  p_reason text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_site uuid; v_worker uuid; v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_event_type not in ('clock_in','clock_out') then raise exception 'invalid event type'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 5 and 500 then raise exception 'override reason required'; end if;
  select public.current_app_role() into v_role;
  select sh.site_id,a.worker_id into v_site,v_worker
    from public.shift_assignments a join public.shifts sh on sh.id=a.shift_id
   where a.id=p_assignment_id and a.cancelled_at is null and a.accepted_at is not null;
  if v_site is null then raise exception 'assignment not available'; end if;
  if v_role='supervisor' and not exists(select 1 from public.supervisor_sites ss where ss.supervisor_id=auth.uid() and ss.site_id=v_site) then
    raise exception 'site not assigned to supervisor';
  end if;
  if v_role not in ('supervisor','ops_manager','admin') then raise exception 'not authorised'; end if;

  insert into public.attendance_verification_evidence(
    assignment_id,worker_id,event_type,verification_method,result,override_reason,verified_at,expires_at,recorded_by
  ) values(p_assignment_id,v_worker,p_event_type,'manual_fallback','passed',trim(p_reason),now(),now()+interval '10 minutes',auth.uid())
  returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.manual_fallback_created','attendance_verification',v_id,
    jsonb_build_object('assignment_id',p_assignment_id,'site_id',v_site,'event_type',p_event_type,'reason',left(trim(p_reason),120)));
  return v_id;
end $$;

revoke all on function public.create_attendance_manual_fallback(uuid,text,text) from public;
grant execute on function public.create_attendance_manual_fallback(uuid,text,text) to authenticated;

-- Enforce enhanced policy immediately before time evidence is accepted.
-- facial_optional never blocks GPS attendance; facial_required accepts either provider-validated 1:1 evidence or an audited manual fallback.
create or replace function public.enforce_attendance_verification_policy()
returns trigger
language plpgsql security definer set search_path=public as $$
declare v_level text; v_worker uuid; v_evidence uuid;
begin
  if new.event_type not in ('clock_in','clock_out') then return new; end if;
  select s.attendance_security_level,a.worker_id into v_level,v_worker
    from public.shift_assignments a
    join public.shifts sh on sh.id=a.shift_id
    join public.sites s on s.id=sh.site_id
   where a.id=new.assignment_id;
  if coalesce(v_level,'gps_only')<>'facial_required' then return new; end if;
  if new.created_by is distinct from v_worker then return new; end if;

  update public.attendance_verification_evidence e
     set used_at=now()
   where e.id=(
     select id from public.attendance_verification_evidence
      where assignment_id=new.assignment_id
        and worker_id=v_worker
        and event_type=new.event_type
        and result='passed'
        and used_at is null
        and expires_at>=now()
      order by verified_at desc
      limit 1
      for update skip locked
   )
   returning e.id into v_evidence;
  if v_evidence is null then raise exception 'enhanced attendance verification or supervisor fallback required'; end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_worker,'attendance.enhanced_verification_consumed','attendance_verification',v_evidence,
    jsonb_build_object('assignment_id',new.assignment_id,'event_type',new.event_type));
  return new;
end $$;

revoke all on function public.enforce_attendance_verification_policy() from public;

drop trigger if exists trg_enforce_attendance_verification_policy on public.time_events;
create trigger trg_enforce_attendance_verification_policy
before insert on public.time_events
for each row execute function public.enforce_attendance_verification_policy();

comment on column public.sites.attendance_security_level is 'gps_only is default; facial_optional records optional 1:1 evidence; facial_required needs 1:1 evidence or audited manual fallback.';
comment on table public.attendance_biometric_consents is 'Explicit attendance-biometric consent state. Opt-out must not prevent non-biometric/manual attendance fallback.';
comment on table public.attendance_verification_evidence is 'Short-lived 1:1 verification evidence or audited manual fallback. Raw selfies and biometric templates are intentionally not stored.';
