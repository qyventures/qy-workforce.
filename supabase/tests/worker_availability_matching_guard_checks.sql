-- Structural regression checks for availability-aware matching and acceptance.

do $$
declare v_def text;
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='worker_has_approved_availability_conflict'
      and p.prosecdef and p.proconfig @> array['search_path=public']
  ) then raise exception 'availability conflict predicate must be fixed-search-path SECURITY DEFINER'; end if;

  select pg_get_functiondef('public.worker_has_approved_availability_conflict(uuid,timestamptz,timestamptz)'::regprocedure) into v_def;
  if position('status = ''approved''' in lower(v_def)) = 0
     or position('starts_at < p_ends_at' in lower(v_def)) = 0
     or position('ends_at > p_starts_at' in lower(v_def)) = 0 then
    raise exception 'availability predicate must use approved interval overlap only';
  end if;

  select pg_get_functiondef('public.get_available_shifts()'::regprocedure) into v_def;
  if position('worker_has_approved_availability_conflict' in lower(v_def)) = 0 then
    raise exception 'shift discovery must exclude approved availability conflicts';
  end if;

  select pg_get_functiondef('public.accept_shift(uuid)'::regprocedure) into v_def;
  if position('worker_has_approved_availability_conflict' in lower(v_def)) = 0
     or position('worker unavailable for shift' in lower(v_def)) = 0 then
    raise exception 'shift acceptance must reject approved availability conflicts';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon','public.worker_has_approved_availability_conflict(uuid,timestamptz,timestamptz)','EXECUTE') then
    raise exception 'anon must not execute availability predicate directly';
  end if;
  if not has_function_privilege('authenticated','public.get_available_shifts()','EXECUTE')
     or not has_function_privilege('authenticated','public.accept_shift(uuid)','EXECUTE') then
    raise exception 'authenticated matching RPC grants must remain available';
  end if;
end;
$$;
