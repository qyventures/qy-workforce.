-- Structural regression checks for client SLA tracking and demand forecasting.

do $$
begin
  if not has_function_privilege('authenticated','public.upsert_client_sla_policy(uuid,uuid,numeric,integer,text,boolean)','EXECUTE') then
    raise exception 'authenticated execute grant missing for SLA policy RPC';
  end if;
  if has_function_privilege('anon','public.upsert_client_sla_policy(uuid,uuid,numeric,integer,text,boolean)','EXECUTE') then
    raise exception 'anon must not execute SLA policy RPC';
  end if;
  if has_table_privilege('authenticated','public.client_sla_policies','INSERT')
     or has_table_privilege('authenticated','public.client_sla_policies','UPDATE')
     or has_table_privilege('authenticated','public.client_sla_policies','DELETE') then
    raise exception 'authenticated direct SLA policy mutation must remain blocked';
  end if;

  if not has_function_privilege('authenticated','public.get_client_sla_dashboard(integer,uuid)','EXECUTE') then
    raise exception 'authenticated execute grant missing for SLA dashboard';
  end if;
  if has_function_privilege('anon','public.get_client_sla_dashboard(integer,uuid)','EXECUTE') then
    raise exception 'anon must not execute SLA dashboard';
  end if;
  if not has_function_privilege('authenticated','public.get_ops_demand_forecast(integer,integer,uuid)','EXECUTE') then
    raise exception 'authenticated execute grant missing for demand forecast';
  end if;
  if has_function_privilege('anon','public.get_ops_demand_forecast(integer,integer,uuid)','EXECUTE') then
    raise exception 'anon must not execute demand forecast';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_client_sla_dashboard'
      and p.prosecdef and p.proconfig @> array['search_path=public']
  ) then raise exception 'SLA dashboard must be SECURITY DEFINER with fixed search_path'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_demand_forecast'
      and p.prosecdef and p.proconfig @> array['search_path=public']
  ) then raise exception 'demand forecast must be SECURITY DEFINER with fixed search_path'; end if;

  if position('public.is_ops()' in pg_get_functiondef('public.get_client_sla_dashboard(integer,uuid)'::regprocedure))=0 then
    raise exception 'SLA dashboard must enforce Ops authorization';
  end if;
  if position('public.is_ops()' in pg_get_functiondef('public.get_ops_demand_forecast(integer,integer,uuid)'::regprocedure))=0 then
    raise exception 'demand forecast must enforce Ops authorization';
  end if;
  if position('public.shifts' in pg_get_functiondef('public.get_ops_demand_forecast(integer,integer,uuid)'::regprocedure))=0 then
    raise exception 'demand forecast must derive from historical shifts';
  end if;
  if position('insert into public.shift_assignments' in lower(pg_get_functiondef('public.get_ops_demand_forecast(integer,integer,uuid)'::regprocedure)))>0
     or position('update public.shifts' in lower(pg_get_functiondef('public.get_ops_demand_forecast(integer,integer,uuid)'::regprocedure)))>0 then
    raise exception 'demand forecast must remain decision support only';
  end if;
end;
$$;
