-- Structural regression checks for the privileged, read-only management cockpit.
do $$
declare
  v_def text;
  v_prosec boolean;
  v_config text[];
  v_anon boolean;
begin
  select p.prosecdef,p.proconfig,pg_get_functiondef(p.oid)
    into v_prosec,v_config,v_def
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname='get_management_cockpit'
     and pg_get_function_identity_arguments(p.oid)='p_as_of timestamp with time zone';

  if v_def is null then raise exception 'get_management_cockpit missing'; end if;
  if not v_prosec then raise exception 'management cockpit must be SECURITY DEFINER'; end if;
  if v_config is null or not ('search_path=public'=any(v_config)) then
    raise exception 'management cockpit must pin search_path';
  end if;
  if position('auth.uid() is null' in v_def)=0 then raise exception 'authentication guard missing'; end if;
  if position('ops_manager' in v_def)=0 or position('finance' in v_def)=0
     or position('admin' in v_def)=0 or position('auditor' in v_def)=0 then
    raise exception 'privileged role boundary missing';
  end if;
  if position('client_billing_items' in v_def)=0 or position('payroll_batches' in v_def)=0
     or position('labour_requisitions' in v_def)=0 or position('time_events' in v_def)=0 then
    raise exception 'cockpit coverage regression';
  end if;
  if position('insert into' in lower(v_def))>0 or position('update public.' in lower(v_def))>0
     or position('delete from' in lower(v_def))>0 then
    raise exception 'management cockpit must remain read-only';
  end if;

  select has_function_privilege('anon','public.get_management_cockpit(timestamp with time zone)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not execute management cockpit'; end if;

  if not has_function_privilege('authenticated','public.get_management_cockpit(timestamp with time zone)','EXECUTE') then
    raise exception 'authenticated role needs RPC execute before app-role enforcement';
  end if;
end;
$$;