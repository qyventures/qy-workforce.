-- Structural regression checks for client billing ledger controls.

do $$
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='client_billing_items' and c.relrowsecurity
  ) then
    raise exception 'client_billing_items must have RLS enabled';
  end if;

  if has_table_privilege('authenticated','public.client_billing_items','INSERT')
     or has_table_privilege('authenticated','public.client_billing_items','UPDATE')
     or has_table_privilege('authenticated','public.client_billing_items','DELETE') then
    raise exception 'authenticated users must not directly mutate client billing';
  end if;

  if not has_function_privilege('authenticated','public.sync_client_billing_items(date,date)','EXECUTE')
     or not has_function_privilege('authenticated','public.transition_client_billing_item(uuid,text,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_client_billing_summary(date,date)','EXECUTE') then
    raise exception 'client billing RPC grant missing';
  end if;

  if has_function_privilege('anon','public.sync_client_billing_items(date,date)','EXECUTE')
     or has_function_privilege('anon','public.transition_client_billing_item(uuid,text,text,text)','EXECUTE')
     or has_function_privilege('anon','public.get_client_billing_summary(date,date)','EXECUTE') then
    raise exception 'anon must not execute client billing RPCs';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname in ('sync_client_billing_items','transition_client_billing_item','get_client_billing_summary')
        and p.prosecdef and p.proconfig @> array['search_path=public']) <> 3 then
    raise exception 'client billing RPCs must be SECURITY DEFINER with fixed search_path';
  end if;

  if position('current_app_role() not in' in pg_get_functiondef('public.sync_client_billing_items(date,date)'::regprocedure)) = 0 then
    raise exception 'billing sync must enforce finance/admin authorization';
  end if;
  if position('current_app_role() not in' in pg_get_functiondef('public.transition_client_billing_item(uuid,text,text,text)'::regprocedure)) = 0 then
    raise exception 'billing transition must enforce finance/admin authorization';
  end if;
  if position('timesheets' in pg_get_functiondef('public.sync_client_billing_items(date,date)'::regprocedure)) = 0
     or position('payroll_ready' in pg_get_functiondef('public.sync_client_billing_items(date,date)'::regprocedure)) = 0
     or position('approved' in pg_get_functiondef('public.sync_client_billing_items(date,date)'::regprocedure)) = 0 then
    raise exception 'billing sync must source approved/payroll-ready timesheets';
  end if;
  if position('financial snapshot is immutable' in pg_get_functiondef('public.protect_client_billing_snapshot()'::regprocedure)) = 0 then
    raise exception 'billing financial snapshot guard missing';
  end if;
end;
$$;