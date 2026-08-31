-- Structural regression checks for employer CRM tables and RPC boundaries.

do $$
declare v_table text;
begin
  foreach v_table in array array['client_contacts','client_contracts','client_feedback'] loop
    if to_regclass('public.' || v_table) is null then raise exception '% table missing', v_table; end if;
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table and c.relrowsecurity
    ) then raise exception 'RLS must be enabled on %', v_table; end if;
    if has_table_privilege('authenticated','public.' || v_table,'INSERT')
       or has_table_privilege('authenticated','public.' || v_table,'UPDATE')
       or has_table_privilege('authenticated','public.' || v_table,'DELETE') then
      raise exception 'authenticated must not mutate % directly', v_table;
    end if;
    if has_table_privilege('anon','public.' || v_table,'INSERT')
       or has_table_privilege('anon','public.' || v_table,'UPDATE')
       or has_table_privilege('anon','public.' || v_table,'DELETE') then
      raise exception 'anon must not mutate % directly', v_table;
    end if;
  end loop;

  if not has_function_privilege('authenticated','public.save_client_contact(uuid,text,text,text,text,boolean)','EXECUTE') then
    raise exception 'contact RPC grant missing';
  end if;
  if not has_function_privilege('authenticated','public.create_client_contract(uuid,text,date,date,integer,text)','EXECUTE') then
    raise exception 'contract RPC grant missing';
  end if;
  if not has_function_privilege('authenticated','public.record_client_feedback(uuid,uuid,text,text,text,text,uuid)','EXECUTE') then
    raise exception 'feedback RPC grant missing';
  end if;
  if has_function_privilege('anon','public.save_client_contact(uuid,text,text,text,text,boolean)','EXECUTE')
     or has_function_privilege('anon','public.create_client_contract(uuid,text,date,date,integer,text)','EXECUTE')
     or has_function_privilege('anon','public.record_client_feedback(uuid,uuid,text,text,text,text,uuid)','EXECUTE') then
    raise exception 'anon must not execute employer CRM mutation RPCs';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('save_client_contact','create_client_contract','record_client_feedback')
        and p.prosecdef and p.proconfig @> array['search_path=public']) <> 3 then
    raise exception 'employer CRM RPCs must be SECURITY DEFINER with fixed search_path';
  end if;
end;
$$;
