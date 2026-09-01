-- Tighten the optional biometric attendance boundary. Provider-attempt hashes are
-- confidential correlation data, consent withdrawal takes effect before evidence
-- consumption, and a provider callback cannot replay one attempt as many proofs.
-- This does not change the GPS-only default or the audited manual fallback path.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.attendance_verification_evidence'::regclass
      and conname = 'attendance_verification_provider_attempt_hash_check'
  ) then
    alter table public.attendance_verification_evidence
      add constraint attendance_verification_provider_attempt_hash_check
      check (
        provider_attempt_hash is null
        or provider_attempt_hash ~ '^[0-9a-f]{32,128}$'
      ) not valid;
  end if;
end;
$$;

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
declare
  v_id uuid;
  v_assignment_worker uuid;
  v_consent text;
  v_attempt_hash text := lower(nullif(trim(p_provider_attempt_hash), ''));
begin
  if p_event_type not in ('clock_in','clock_out') then raise exception 'invalid event type'; end if;
  if p_result not in ('passed','failed') then raise exception 'invalid result'; end if;
  if v_attempt_hash is null or v_attempt_hash !~ '^[0-9a-f]{32,128}$' then
    raise exception 'invalid provider attempt reference';
  end if;
  if p_verified_at is null or p_verified_at > now()+interval '5 minutes' or p_verified_at < now()-interval '15 minutes' then raise exception 'invalid verification time'; end if;

  -- Serialize on the opaque provider attempt so concurrent callbacks cannot turn
  -- one liveness assertion into multiple independently consumable records.
  perform pg_advisory_xact_lock(hashtextextended(v_attempt_hash, 0));
  if exists (
    select 1 from public.attendance_verification_evidence e
    where e.provider_attempt_hash = v_attempt_hash
  ) then raise exception 'provider attempt already recorded'; end if;

  select worker_id into v_assignment_worker from public.shift_assignments where id=p_assignment_id and cancelled_at is null and accepted_at is not null;
  if v_assignment_worker is null or v_assignment_worker<>p_worker_id then raise exception 'assignment worker mismatch'; end if;
  select status into v_consent from public.attendance_biometric_consents where worker_id=p_worker_id;
  if coalesce(v_consent,'opted_out')<>'opted_in' then raise exception 'active biometric consent required'; end if;
  if p_result='passed' and (p_liveness_passed is distinct from true or p_match_passed is distinct from true) then raise exception 'passed verification requires liveness and 1:1 match'; end if;

  insert into public.attendance_verification_evidence(
    assignment_id,worker_id,event_type,verification_method,result,provider_attempt_hash,liveness_passed,match_passed,verified_at,expires_at,recorded_by
  ) values(
    p_assignment_id,p_worker_id,p_event_type,'selfie_liveness_1to1',p_result,v_attempt_hash,p_liveness_passed,p_match_passed,p_verified_at,p_verified_at+interval '10 minutes',null
  ) returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(null,'attendance.biometric_result_recorded','attendance_verification',v_id,
    jsonb_build_object('assignment_id',p_assignment_id,'event_type',p_event_type,'result',p_result));
  return v_id;
end $$;

revoke all on function public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamptz) from public, anon, authenticated;
grant execute on function public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamptz) to service_role;

create or replace function public.enforce_attendance_verification_policy()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_level text;
  v_worker uuid;
  v_evidence uuid;
  v_method text;
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
      where assignment_id=new.assignment_id and worker_id=v_worker and event_type=new.event_type
        and result='passed' and used_at is null and expires_at>=now()
        -- A withdrawal must prevent use of a previously captured biometric proof.
        -- Manual fallback remains available because it does not process biometrics.
        and (verification_method='manual_fallback' or exists (
          select 1 from public.attendance_biometric_consents c
           where c.worker_id=v_worker and c.status='opted_in'
        ))
      order by verified_at desc
      limit 1
      for update skip locked
   )
   returning e.id, e.verification_method into v_evidence, v_method;
  if v_evidence is null then raise exception 'enhanced attendance verification or supervisor fallback required'; end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_worker,'attendance.enhanced_verification_consumed','attendance_verification',v_evidence,
    jsonb_build_object('assignment_id',new.assignment_id,'event_type',new.event_type,'method',v_method));
  return new;
end $$;
revoke all on function public.enforce_attendance_verification_policy() from public, anon, authenticated;

-- RLS alone is not enough when a table may later receive a broad SELECT grant.
-- Provider-attempt hashes are not needed by workers, so expose a minimal status
-- projection through an explicit worker-scoped RPC instead of raw evidence rows.
revoke select on table public.attendance_verification_evidence from anon, authenticated;

create or replace function public.get_own_attendance_verification_status()
returns table (
  assignment_id uuid,
  event_type text,
  verification_method text,
  result text,
  verified_at timestamptz,
  expires_at timestamptz,
  used_at timestamptz
)
language sql stable security definer set search_path=public as $$
  select e.assignment_id, e.event_type, e.verification_method, e.result,
         e.verified_at, e.expires_at, e.used_at
    from public.attendance_verification_evidence e
   where e.worker_id=auth.uid()
   order by e.verified_at desc, e.id desc;
$$;
revoke all on function public.get_own_attendance_verification_status() from public;
grant execute on function public.get_own_attendance_verification_status() to authenticated;

comment on function public.get_own_attendance_verification_status() is
  'Worker-scoped attendance-verification status without confidential provider-attempt hashes or biometric data.';
comment on function public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamptz) is
  'Service-only callback boundary. Accepts one normalized hexadecimal provider-attempt hash once; raw biometric material is never stored.';
