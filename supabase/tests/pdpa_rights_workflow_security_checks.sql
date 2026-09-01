-- Structural regression checks for PDPA access/correction/deletion workflow.
do $$
declare
  v_def text;
  v_direct boolean;
  v_anon boolean;
begin
  if to_regclass('public.privacy_requests') is null then raise exception 'privacy_requests missing'; end if;
  if to_regclass('public.privacy_request_events') is null then raise exception 'privacy_request_events missing'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='privacy_requests' and column_name='requester_id') then raise exception 'privacy_requests requester_id compatibility column missing'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='privacy_requests' and column_name='request_details') then raise exception 'privacy_requests request_details missing'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='privacy_requests' and column_name='correction_target') then raise exception 'privacy_requests correction_target missing'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='privacy_requests' and column_name='legal_hold') then raise exception 'privacy_requests legal_hold missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.privacy_requests'::regclass) then raise exception 'privacy_requests RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.privacy_request_events'::regclass) then raise exception 'privacy_request_events RLS missing'; end if;

  select has_table_privilege('authenticated','public.privacy_requests','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct privacy request mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.privacy_request_events','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct privacy event mutation must remain denied'; end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='submit_my_privacy_request';
  if v_def is null then raise exception 'submit_my_privacy_request missing'; end if;
  if position('security definer' in lower(v_def))=0 then raise exception 'submit privacy RPC must be SECURITY DEFINER'; end if;
  if position('set search_path=public' in replace(lower(v_def),' ',''))=0
     and position('set search_path = public' in lower(v_def))=0 then raise exception 'submit privacy RPC must pin search_path'; end if;
  if position('open request of this type already exists' in v_def)=0 then raise exception 'duplicate-open-request guard missing'; end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='admin_transition_privacy_request';
  if v_def is null then raise exception 'admin_transition_privacy_request missing'; end if;
  if position('admin required' in v_def)=0 then raise exception 'admin transition guard missing'; end if;
  if position('invalid privacy request transition' in v_def)=0 then raise exception 'privacy state-machine guard missing'; end if;
  if position('cannot complete while legal hold is active' in v_def)=0 then raise exception 'legal-hold completion guard missing'; end if;
  if position('security definer' in lower(v_def))=0 then raise exception 'admin privacy RPC must be SECURITY DEFINER'; end if;

  select has_function_privilege('anon','public.submit_my_privacy_request(text,text,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not submit privacy requests'; end if;
  select has_function_privilege('anon','public.withdraw_my_privacy_request(uuid,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not withdraw privacy requests'; end if;
  select has_function_privilege('anon','public.admin_transition_privacy_request(uuid,text,text,uuid,boolean,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not transition privacy requests'; end if;
end;
$$;
