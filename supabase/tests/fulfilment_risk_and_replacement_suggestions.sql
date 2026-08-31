-- Structural regression checks for fulfilment-risk and replacement suggestion RPCs.

do $$
begin
  if not has_function_privilege('authenticated','public.get_ops_fulfilment_risk(timestamptz,timestamptz)','EXECUTE') then
    raise exception 'fulfilment risk grant missing';
  end if;
  if not has_function_privilege('authenticated','public.get_ops_replacement_candidates(uuid,integer)','EXECUTE') then
    raise exception 'replacement candidate grant missing';
  end if;
  if has_function_privilege('anon','public.get_ops_fulfilment_risk(timestamptz,timestamptz)','EXECUTE')
     or has_function_privilege('anon','public.get_ops_replacement_candidates(uuid,integer)','EXECUTE') then
    raise exception 'anon must not execute fulfilment RPCs';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname in ('get_ops_fulfilment_risk','get_ops_replacement_candidates')
        and p.prosecdef and p.proconfig @> array['search_path=public']) <> 2 then
    raise exception 'fulfilment RPCs must be SECURITY DEFINER with fixed search_path';
  end if;

  if position('public.is_ops()' in pg_get_functiondef('public.get_ops_fulfilment_risk(timestamptz,timestamptz)'::regprocedure)) = 0 then
    raise exception 'fulfilment risk RPC must enforce Ops authorization';
  end if;
  if position('public.is_ops()' in pg_get_functiondef('public.get_ops_replacement_candidates(uuid,integer)'::regprocedure)) = 0 then
    raise exception 'replacement RPC must enforce Ops authorization';
  end if;
  if position('public.worker_is_deployable' in pg_get_functiondef('public.get_ops_replacement_candidates(uuid,integer)'::regprocedure)) = 0 then
    raise exception 'replacement suggestions must enforce live deployability';
  end if;
  if position('worker_absences' in pg_get_functiondef('public.get_ops_replacement_candidates(uuid,integer)'::regprocedure)) = 0 then
    raise exception 'replacement suggestions must exclude absence conflicts';
  end if;
  if position('shift_assignments' in pg_get_functiondef('public.get_ops_replacement_candidates(uuid,integer)'::regprocedure)) = 0 then
    raise exception 'replacement suggestions must exclude assignment conflicts';
  end if;
end;
$$;