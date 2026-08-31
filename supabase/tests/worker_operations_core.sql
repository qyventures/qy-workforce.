-- Structural regression checks for worker availability, absence and reliability controls.

do $$
declare v_table text;
begin
  foreach v_table in array array['worker_availability','worker_absences','worker_reliability_events'] loop
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

  if not has_function_privilege('authenticated','public.set_worker_availability(timestamptz,timestamptz,text,text)','EXECUTE') then
    raise exception 'availability RPC grant missing';
  end if;
  if not has_function_privilege('authenticated','public.report_worker_absence(text,timestamptz,timestamptz,text,text)','EXECUTE') then
    raise exception 'absence report RPC grant missing';
  end if;
  if not has_function_privilege('authenticated','public.review_worker_absence(uuid,text)','EXECUTE') then
    raise exception 'absence review RPC grant missing';
  end if;
  if not has_function_privilege('authenticated','public.record_worker_reliability_event(uuid,text,integer,text,uuid,text)','EXECUTE') then
    raise exception 'reliability event RPC grant missing';
  end if;
  if not has_function_privilege('authenticated','public.get_worker_reliability_summary(uuid)','EXECUTE') then
    raise exception 'reliability summary RPC grant missing';
  end if;

  if has_function_privilege('anon','public.set_worker_availability(timestamptz,timestamptz,text,text)','EXECUTE')
     or has_function_privilege('anon','public.report_worker_absence(text,timestamptz,timestamptz,text,text)','EXECUTE')
     or has_function_privilege('anon','public.review_worker_absence(uuid,text)','EXECUTE')
     or has_function_privilege('anon','public.record_worker_reliability_event(uuid,text,integer,text,uuid,text)','EXECUTE')
     or has_function_privilege('anon','public.get_worker_reliability_summary(uuid)','EXECUTE') then
    raise exception 'anon must not execute worker operations RPCs';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname in ('set_worker_availability','report_worker_absence','review_worker_absence','record_worker_reliability_event','get_worker_reliability_summary')
        and p.prosecdef and p.proconfig @> array['search_path=public']) <> 5 then
    raise exception 'worker operations RPCs must be SECURITY DEFINER with fixed search_path';
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='worker_reliability_events'
      and policyname='privileged read reliability events'
  ) then raise exception 'reliability events privileged read policy missing'; end if;
end;
$$;
