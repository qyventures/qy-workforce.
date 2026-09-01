-- Structural safety checks for optional biometric attendance governance.

do $$
declare v_rls boolean;
begin
  select relrowsecurity into v_rls from pg_class where oid='public.site_attendance_security'::regclass;
  if not v_rls then raise exception 'site attendance security must have RLS enabled'; end if;
  select relrowsecurity into v_rls from pg_class where oid='public.worker_biometric_consents'::regclass;
  if not v_rls then raise exception 'worker biometric consents must have RLS enabled'; end if;
  select relrowsecurity into v_rls from pg_class where oid='public.attendance_verification_events'::regclass;
  if not v_rls then raise exception 'attendance verification events must have RLS enabled'; end if;
end $$;

do $$
declare v_has_write boolean;
begin
  select has_table_privilege('authenticated','public.site_attendance_security','insert,update,delete') into v_has_write;
  if v_has_write then raise exception 'authenticated must not directly write site attendance security'; end if;
  select has_table_privilege('authenticated','public.worker_biometric_consents','insert,update,delete') into v_has_write;
  if v_has_write then raise exception 'authenticated must not directly write biometric consents'; end if;
  select has_table_privilege('authenticated','public.attendance_verification_events','insert,update,delete') into v_has_write;
  if v_has_write then raise exception 'authenticated must not directly write attendance verification events'; end if;
end $$;

do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.worker_set_biometric_consent(boolean,text)'::regprocedure) into v_sql;
  if position('consent version required' in v_sql)=0 then raise exception 'biometric opt-in must require a consent version'; end if;
  if position('template_reference=null' in replace(lower(v_sql),' ',''))=0 then raise exception 'consent withdrawal must clear template reference'; end if;
end $$;

do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.ops_set_site_attendance_security(uuid,text,boolean,integer,text)'::regprocedure) into v_sql;
  if position('gps_only' in v_sql)=0 then raise exception 'site security RPC must preserve gps-only level'; end if;
  if position('raw_image_retention_hours=0' in replace(lower(v_sql),' ',''))=0 then raise exception 'site security RPC must force zero raw image retention'; end if;
  if position('fallback_method' in v_sql)=0 then raise exception 'site security RPC must require a fallback method'; end if;
end $$;

do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.ops_record_attendance_manual_override(uuid,uuid,text,text,text)'::regprocedure) into v_sql;
  if position('override reason required' in v_sql)=0 then raise exception 'manual override must require an audit reason'; end if;
  if position('supervisor_sites' in v_sql)=0 then raise exception 'manual override must preserve supervisor site authorization'; end if;
  if position('time event does not belong to assignment' in v_sql)=0 then raise exception 'manual override must bind evidence to the assignment'; end if;
end $$;

do $$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid='public.attendance_verification_events'::regclass
    and contype='c'
    and pg_get_constraintdef(oid) ilike '%raw_image_retained%';
  if v_def is null or position('NOT raw_image_retained' in upper(v_def))=0 then
    raise exception 'attendance verification events must prohibit raw image retention';
  end if;
end $$;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'worker_set_biometric_consent',
    'ops_set_site_attendance_security',
    'ops_record_attendance_manual_override'
  ) and p.prosecdef;
  if v_count <> 3 then raise exception 'biometric governance mutation RPCs must be SECURITY DEFINER'; end if;
end $$;
