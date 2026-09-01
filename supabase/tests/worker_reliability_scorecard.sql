-- Structural regression checks for the Ops worker reliability scorecard.

do $$
begin
  if not has_function_privilege(
    'authenticated',
    'public.get_ops_worker_reliability_scorecard(uuid,integer,integer)',
    'EXECUTE'
  ) then
    raise exception 'authenticated execute grant missing';
  end if;

  if has_function_privilege(
    'anon',
    'public.get_ops_worker_reliability_scorecard(uuid,integer,integer)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute reliability scorecard';
  end if;

  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'get_ops_worker_reliability_scorecard'
       and p.prosecdef
       and p.proconfig @> array['search_path=public']
  ) then
    raise exception 'reliability scorecard must be SECURITY DEFINER with fixed search_path';
  end if;

  if position(
    'public.is_ops()' in pg_get_functiondef(
      'public.get_ops_worker_reliability_scorecard(uuid,integer,integer)'::regprocedure
    )
  ) = 0 then
    raise exception 'reliability scorecard must enforce Ops authorization';
  end if;

  if position(
    'worker_reliability_events' in pg_get_functiondef(
      'public.get_ops_worker_reliability_scorecard(uuid,integer,integer)'::regprocedure
    )
  ) = 0 then
    raise exception 'reliability scorecard must derive from audited reliability events';
  end if;

  if position(
    'worker_is_deployable' in pg_get_functiondef(
      'public.get_ops_worker_reliability_scorecard(uuid,integer,integer)'::regprocedure
    )
  ) = 0 then
    raise exception 'reliability scorecard must expose live deployability separately';
  end if;
end;
$$;
