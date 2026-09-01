-- Structural regression checks for full-time vacancy and applicant tracking controls.
do $$
declare
  v_def text;
  v_direct boolean;
  v_anon boolean;
begin
  if to_regclass('public.full_time_jobs') is null then raise exception 'full-time jobs table missing'; end if;
  if to_regclass('public.full_time_applications') is null then raise exception 'full-time applications table missing'; end if;
  if to_regclass('public.full_time_application_events') is null then raise exception 'full-time application events table missing'; end if;

  if not (select relrowsecurity from pg_class where oid='public.full_time_jobs'::regclass) then raise exception 'full-time jobs RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.full_time_applications'::regclass) then raise exception 'full-time applications RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.full_time_application_events'::regclass) then raise exception 'full-time application events RLS missing'; end if;

  select has_table_privilege('authenticated','public.full_time_jobs','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct full-time job mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.full_time_applications','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct application mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.full_time_application_events','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct application event mutation must remain denied'; end if;

  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='apply_to_full_time_job';
  if v_def is null then raise exception 'full-time apply RPC missing'; end if;
  if position('security definer' in lower(v_def))=0 then raise exception 'full-time apply RPC must be SECURITY DEFINER'; end if;
  if position('job is not open for applications' in v_def)=0 then raise exception 'published/open application guard missing'; end if;
  if position('work eligibility requires review' in v_def)=0 then raise exception 'worker eligibility guard missing'; end if;

  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='review_full_time_application';
  if v_def is null then raise exception 'application review RPC missing'; end if;
  if position('invalid application transition' in v_def)=0 then raise exception 'application state transition guard missing'; end if;
  if position('full_time_application.reviewed' in v_def)=0 then raise exception 'application review audit event missing'; end if;

  select has_function_privilege('anon','public.create_full_time_job_draft(uuid,text,text,text,uuid,uuid,text,text,text,integer,numeric,numeric,text,timestamptz)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not create full-time jobs'; end if;
  select has_function_privilege('anon','public.apply_to_full_time_job(uuid,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not submit full-time applications'; end if;
  select has_function_privilege('anon','public.review_full_time_application(uuid,text,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not review applications'; end if;
end;
$$;
