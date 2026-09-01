-- Regression checks for biometric-consent withdrawal, replay resistance and
-- the minimum-disclosure worker status projection.
begin;

do $$
declare
  v_record text;
  v_enforce text;
  v_status text;
begin
  select pg_get_functiondef('public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamp with time zone)'::regprocedure) into v_record;
  select pg_get_functiondef('public.enforce_attendance_verification_policy()'::regprocedure) into v_enforce;
  select pg_get_functiondef('public.get_own_attendance_verification_status()'::regprocedure) into v_status;

  if v_record not ilike '%pg_advisory_xact_lock%' or v_record not ilike '%provider attempt already recorded%'
     or v_record not ilike '%^[0-9a-f]{32,128}$%' then
    raise exception 'biometric callback must serialize and reject provider-attempt replay';
  end if;
  if v_enforce not ilike '%attendance_biometric_consents%' or v_enforce not ilike '%c.status=''opted_in''%'
     or v_enforce not ilike '%verification_method=''manual_fallback''%' then
    raise exception 'biometric consent withdrawal must block proof consumption while preserving manual fallback';
  end if;
  if v_status ilike '%provider_attempt_hash%' then
    raise exception 'worker attendance-verification status must not expose provider attempt hashes';
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon','public.attendance_verification_evidence','SELECT')
     or has_table_privilege('authenticated','public.attendance_verification_evidence','SELECT') then
    raise exception 'API roles must not directly select attendance verification evidence';
  end if;
  if has_function_privilege('anon','public.get_own_attendance_verification_status()','EXECUTE') then
    raise exception 'anonymous callers must not read attendance verification status';
  end if;
  if not has_function_privilege('authenticated','public.get_own_attendance_verification_status()','EXECUTE') then
    raise exception 'authenticated workers require the minimal verification status RPC';
  end if;
  if has_function_privilege('authenticated','public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamp with time zone)','EXECUTE') then
    raise exception 'authenticated clients must not record provider results';
  end if;
end;
$$;

rollback;
