-- Structural regression checks for live deployability at worker clock-in.

do $$
declare
  v_def text;
  v_trigger_count integer;
begin
  select pg_get_functiondef('public.guard_worker_clock_in_deployability()'::regprocedure) into v_def;

  if position('worker_has_deployment_prerequisites(v_worker)' in v_def) = 0 then
    raise exception 'clock-in guard must enforce live deployability';
  end if;

  if position("new.event_type is distinct from 'clock_in'" in v_def) = 0 then
    raise exception 'guard must be scoped to clock-in so clock-out remains available';
  end if;

  if position("new.source is distinct from 'worker_app'" in v_def) = 0 then
    raise exception 'guard must be scoped to worker-app attendance';
  end if;

  if position('new.created_by is distinct from v_worker' in v_def) = 0 then
    raise exception 'clock-in guard must bind event creator to assigned worker';
  end if;

  if position('auth.uid() is not null and auth.uid() is distinct from v_worker' in v_def) = 0 then
    raise exception 'clock-in guard must reject authenticated actor mismatch';
  end if;

  select count(*) into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname='time_events'
    and t.tgname='time_events_worker_clock_in_deployability_guard'
    and not t.tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'time_events live deployability trigger must exist exactly once';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon','public.guard_worker_clock_in_deployability()','EXECUTE')
     or has_function_privilege('authenticated','public.guard_worker_clock_in_deployability()','EXECUTE') then
    raise exception 'clock-in trigger helper must not be directly executable by client roles';
  end if;
end;
$$;
