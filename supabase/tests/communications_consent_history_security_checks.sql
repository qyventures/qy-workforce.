-- Structural regression checks for consent-aware communication history.
do $$
declare
  v_def text;
  v_anon boolean;
  v_direct boolean;
begin
  if to_regclass('public.communication_preferences') is null then raise exception 'communication_preferences missing'; end if;
  if to_regclass('public.communication_events') is null then raise exception 'communication_events missing'; end if;
  if to_regclass('public.communication_escalations') is null then raise exception 'communication_escalations missing'; end if;

  if not (select relrowsecurity from pg_class where oid='public.communication_preferences'::regclass) then raise exception 'preferences RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.communication_events'::regclass) then raise exception 'events RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.communication_escalations'::regclass) then raise exception 'escalations RLS missing'; end if;

  select has_table_privilege('authenticated','public.communication_preferences','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct preference mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.communication_events','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct event mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.communication_escalations','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct escalation mutation must remain denied'; end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='record_communication_event';
  if v_def is null then raise exception 'record_communication_event missing'; end if;
  if position('security definer' in lower(v_def))=0 then raise exception 'communication event RPC must be SECURITY DEFINER'; end if;
  if position('set search_path=public' in replace(lower(v_def),' ',''))=0
     and position('set search_path = public' in lower(v_def))=0 then raise exception 'communication event RPC must pin search_path'; end if;
  if position('active channel opt-in required' in v_def)=0 then raise exception 'outbound opt-in guard missing'; end if;
  if position('opted_out' in v_def)=0 or position('opt_out' in v_def)=0 then raise exception 'STOP/opt-out handling missing'; end if;

  select has_function_privilege('anon','public.record_communication_event(text,uuid,text,text,text,text,text,timestamp with time zone)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not execute communication event RPC'; end if;
  select has_function_privilege('anon','public.set_communication_preference(text,uuid,text,text,text,timestamp with time zone)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not execute preference RPC'; end if;
  select has_function_privilege('anon','public.create_communication_escalation(text,uuid,text,text,uuid)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not execute escalation RPC'; end if;
end;
$$;
