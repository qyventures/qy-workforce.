-- Structural regression checks for optional attendance facial verification.
do $$
declare
  v_def text;
  v_direct boolean;
  v_anon boolean;
  v_auth boolean;
  v_trigger boolean;
begin
  if to_regclass('public.attendance_biometric_consents') is null then raise exception 'attendance biometric consents missing'; end if;
  if to_regclass('public.attendance_verification_evidence') is null then raise exception 'attendance verification evidence missing'; end if;

  if not (select relrowsecurity from pg_class where oid='public.attendance_biometric_consents'::regclass) then raise exception 'consent RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.attendance_verification_evidence'::regclass) then raise exception 'verification evidence RLS missing'; end if;

  select has_table_privilege('authenticated','public.attendance_biometric_consents','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct biometric consent mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.attendance_verification_evidence','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct verification evidence mutation must remain denied'; end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='record_attendance_biometric_result';
  if v_def is null then raise exception 'biometric result RPC missing'; end if;
  if position('security definer' in lower(v_def))=0 then raise exception 'biometric result RPC must be SECURITY DEFINER'; end if;
  if position('set search_path=public' in replace(lower(v_def),' ',''))=0
     and position('set search_path = public' in lower(v_def))=0 then raise exception 'biometric result RPC must pin search_path'; end if;
  if position('active biometric consent required' in v_def)=0 then raise exception 'consent guard missing'; end if;
  if position('1:1 match' in v_def)=0 then raise exception '1:1 match guard missing'; end if;

  select has_function_privilege('authenticated','public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamp with time zone)','EXECUTE') into v_auth;
  if v_auth then raise exception 'authenticated client must not record biometric provider result'; end if;
  select has_function_privilege('anon','public.record_attendance_biometric_result(uuid,uuid,text,text,text,boolean,boolean,timestamp with time zone)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not record biometric provider result'; end if;

  select exists(
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname='time_events' and t.tgname='trg_enforce_attendance_verification_policy' and not t.tgisinternal
  ) into v_trigger;
  if not v_trigger then raise exception 'attendance verification enforcement trigger missing'; end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='enforce_attendance_verification_policy';
  if position('facial_required' in v_def)=0 then raise exception 'facial_required enforcement missing'; end if;
  if position('gps_only' in v_def)=0 then raise exception 'GPS default boundary missing'; end if;
  if position('manual_fallback' in (select string_agg(pg_get_functiondef(p2.oid),' ') from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace where n2.nspname='public' and p2.proname='create_attendance_manual_fallback'))=0 then
    raise exception 'manual fallback workflow missing';
  end if;

  -- Design invariant: this schema must not create a raw-image/template storage column.
  if exists(
    select 1 from information_schema.columns
     where table_schema='public' and table_name in ('attendance_biometric_consents','attendance_verification_evidence')
       and lower(column_name) similar to '%(image|photo|selfie|template|embedding|vector|face_data)%'
  ) then raise exception 'raw facial image/template storage must remain absent'; end if;
end;
$$;
