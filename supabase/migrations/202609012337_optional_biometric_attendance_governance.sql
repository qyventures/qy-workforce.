-- QY Workforce: optional biometric attendance governance.
-- Default attendance remains authenticated worker + GPS/geofence.
-- This migration adds configurable enhanced verification, explicit consent,
-- non-biometric fallback, retention controls, and audited manual override.
-- It intentionally stores no raw selfie/image payloads and performs no broad facial identification.

create table if not exists public.site_attendance_security (
  site_id uuid primary key references public.sites(id) on delete cascade,
  security_level text not null default 'gps_only'
    check (security_level in ('gps_only','gps_plus_optional_face','gps_plus_required_face_with_fallback')),
  liveness_required boolean not null default true,
  raw_image_retention_hours integer not null default 0 check (raw_image_retention_hours between 0 and 24),
  template_retention_days integer not null default 90 check (template_retention_days between 1 and 365),
  fallback_method text not null default 'supervisor_manual'
    check (fallback_method in ('supervisor_manual','identity_document_manual')),
  configured_by uuid references public.profiles(id),
  configured_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.worker_biometric_consents (
  worker_id uuid primary key references public.worker_profiles(user_id) on delete cascade,
  consent_status text not null default 'not_asked'
    check (consent_status in ('not_asked','opted_in','opted_out','withdrawn')),
  consent_version text,
  consented_at timestamptz,
  withdrawn_at timestamptz,
  template_reference text,
  template_key_version text,
  template_created_at timestamptz,
  template_delete_after timestamptz,
  updated_at timestamptz not null default now(),
  check (template_reference is null or consent_status='opted_in'),
  check (template_delete_after is null or template_created_at is not null)
);

create table if not exists public.attendance_verification_events (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.shift_assignments(id) on delete cascade,
  time_event_id uuid references public.time_events(id) on delete set null,
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  verification_method text not null
    check (verification_method in ('gps_only','face_1to1_liveness','supervisor_manual','identity_document_manual')),
  result text not null check (result in ('passed','failed','fallback_used','manual_approved','manual_rejected')),
  liveness_passed boolean,
  provider_assertion_hash text,
  raw_image_retained boolean not null default false,
  override_reason text check (override_reason is null or char_length(override_reason) between 5 and 1000),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (not raw_image_retained),
  check (verification_method <> 'face_1to1_liveness' or liveness_passed is not null),
  check (verification_method not in ('supervisor_manual','identity_document_manual') or override_reason is not null)
);

create index if not exists attendance_verification_assignment_idx
  on public.attendance_verification_events(assignment_id, created_at desc);
create index if not exists attendance_verification_worker_idx
  on public.attendance_verification_events(worker_id, created_at desc);

alter table public.site_attendance_security enable row level security;
alter table public.worker_biometric_consents enable row level security;
alter table public.attendance_verification_events enable row level security;

revoke insert, update, delete on public.site_attendance_security from anon, authenticated;
revoke insert, update, delete on public.worker_biometric_consents from anon, authenticated;
revoke insert, update, delete on public.attendance_verification_events from anon, authenticated;

create policy "privileged read site attendance security"
on public.site_attendance_security
for select to authenticated using (public.is_privileged());

create policy "workers read own biometric consent"
on public.worker_biometric_consents
for select to authenticated using (worker_id=auth.uid() or public.is_privileged());

create policy "workers read own attendance verification"
on public.attendance_verification_events
for select to authenticated using (worker_id=auth.uid() or public.is_privileged());

create or replace function public.worker_set_biometric_consent(
  p_opt_in boolean,
  p_consent_version text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then
    raise exception 'worker profile required';
  end if;

  if p_opt_in then
    if nullif(trim(coalesce(p_consent_version,'')),'') is null then
      raise exception 'consent version required';
    end if;
    insert into public.worker_biometric_consents(
      worker_id,consent_status,consent_version,consented_at,withdrawn_at,updated_at
    ) values(
      auth.uid(),'opted_in',trim(p_consent_version),now(),null,now()
    ) on conflict(worker_id) do update set
      consent_status='opted_in',consent_version=excluded.consent_version,
      consented_at=now(),withdrawn_at=null,updated_at=now();
  else
    insert into public.worker_biometric_consents(
      worker_id,consent_status,withdrawn_at,updated_at
    ) values(
      auth.uid(),'withdrawn',now(),now()
    ) on conflict(worker_id) do update set
      consent_status='withdrawn',withdrawn_at=now(),
      template_reference=null,template_key_version=null,
      template_delete_after=now(),updated_at=now();
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),
    case when p_opt_in then 'attendance.biometric_consent_opted_in' else 'attendance.biometric_consent_withdrawn' end,
    'worker_profile',auth.uid(),
    jsonb_build_object('consent_version',p_consent_version));
end $$;

create or replace function public.ops_set_site_attendance_security(
  p_site_id uuid,
  p_security_level text,
  p_liveness_required boolean default true,
  p_template_retention_days integer default 90,
  p_fallback_method text default 'supervisor_manual'
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_ops() then raise exception 'ops access required'; end if;
  if p_security_level not in ('gps_only','gps_plus_optional_face','gps_plus_required_face_with_fallback') then
    raise exception 'invalid attendance security level';
  end if;
  if p_template_retention_days not between 1 and 365 then raise exception 'invalid template retention'; end if;
  if p_fallback_method not in ('supervisor_manual','identity_document_manual') then raise exception 'invalid fallback method'; end if;
  if not exists(select 1 from public.sites where id=p_site_id) then raise exception 'site not found'; end if;

  insert into public.site_attendance_security(
    site_id,security_level,liveness_required,raw_image_retention_hours,
    template_retention_days,fallback_method,configured_by,configured_at,updated_at
  ) values(
    p_site_id,p_security_level,coalesce(p_liveness_required,true),0,
    p_template_retention_days,p_fallback_method,auth.uid(),now(),now()
  ) on conflict(site_id) do update set
    security_level=excluded.security_level,
    liveness_required=excluded.liveness_required,
    raw_image_retention_hours=0,
    template_retention_days=excluded.template_retention_days,
    fallback_method=excluded.fallback_method,
    configured_by=auth.uid(),updated_at=now();

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.site_security_configured','site',p_site_id,
    jsonb_build_object('security_level',p_security_level,'fallback_method',p_fallback_method,
      'template_retention_days',p_template_retention_days,'raw_image_retention_hours',0));
end $$;

create or replace function public.ops_record_attendance_manual_override(
  p_assignment_id uuid,
  p_time_event_id uuid,
  p_result text,
  p_reason text,
  p_method text default 'supervisor_manual'
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_worker uuid;
  v_site uuid;
  v_id uuid;
begin
  select a.worker_id, sh.site_id into v_worker,v_site
  from public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  where a.id=p_assignment_id;
  if v_worker is null then raise exception 'assignment not found'; end if;
  if not (public.is_ops() or exists(
    select 1 from public.supervisor_sites ss where ss.site_id=v_site and ss.supervisor_id=auth.uid()
  )) then raise exception 'not authorised'; end if;
  if p_method not in ('supervisor_manual','identity_document_manual') then raise exception 'invalid manual method'; end if;
  if p_result not in ('manual_approved','manual_rejected','fallback_used') then raise exception 'invalid manual result'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null or char_length(trim(p_reason)) < 5 then raise exception 'override reason required'; end if;
  if p_time_event_id is not null and not exists(
    select 1 from public.time_events te where te.id=p_time_event_id and te.assignment_id=p_assignment_id
  ) then raise exception 'time event does not belong to assignment'; end if;

  insert into public.attendance_verification_events(
    assignment_id,time_event_id,worker_id,verification_method,result,
    liveness_passed,provider_assertion_hash,raw_image_retained,override_reason,created_by
  ) values(
    p_assignment_id,p_time_event_id,v_worker,p_method,p_result,
    null,null,false,trim(p_reason),auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.manual_verification_recorded','attendance_verification_event',v_id,
    jsonb_build_object('assignment_id',p_assignment_id,'result',p_result,'method',p_method));
  return v_id;
end $$;

revoke all on function public.worker_set_biometric_consent(boolean,text) from public;
revoke all on function public.ops_set_site_attendance_security(uuid,text,boolean,integer,text) from public;
revoke all on function public.ops_record_attendance_manual_override(uuid,uuid,text,text,text) from public;
grant execute on function public.worker_set_biometric_consent(boolean,text) to authenticated;
grant execute on function public.ops_set_site_attendance_security(uuid,text,boolean,integer,text) to authenticated;
grant execute on function public.ops_record_attendance_manual_override(uuid,uuid,text,text,text) to authenticated;
