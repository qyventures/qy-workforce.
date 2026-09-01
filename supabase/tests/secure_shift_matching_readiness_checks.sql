-- Structural regression checks for matching parity between feed and acceptance.
begin;

do $$
declare
  v_availability text;
  v_accept text;
  v_feed text;
begin
  select pg_get_functiondef('public.worker_is_available_for_shift(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)
    into v_availability;
  if v_availability is null
     or v_availability not ilike '%availability_type = ''unavailable''%'
     or v_availability not ilike '%status in (''reported'', ''reviewed'', ''approved'')%'
     or v_availability not ilike '%wa.starts_at < p_ends_at%'
     or v_availability not ilike '%ab.ends_at > p_starts_at%' then
    raise exception 'availability predicate must block overlapping unavailable windows and active absences';
  end if;

  select pg_get_functiondef('public.accept_shift(uuid)'::regprocedure) into v_accept;
  if v_accept not ilike '%worker_has_deployment_prerequisites(v_worker)%'
     or v_accept not ilike '%worker_is_available_for_shift(v_worker, v_starts_at, v_ends_at)%'
     or v_accept not ilike '%for update of sh%'
     or v_accept not ilike '%pg_advisory_xact_lock%'
     or v_accept not ilike '%v_role_active or not v_site_active or not v_client_active%' then
    raise exception 'acceptance must lock capacity and require live readiness, availability and active demand';
  end if;

  select pg_get_functiondef('public.get_available_shifts()'::regprocedure) into v_feed;
  if v_feed not ilike '%worker_has_deployment_prerequisites(auth.uid())%'
     or v_feed not ilike '%worker_is_available_for_shift(auth.uid(), sh.starts_at, sh.ends_at)%'
     or v_feed not ilike '%r.active and s.active and c.active%' then
    raise exception 'shift feed must match readiness, availability and active-demand acceptance guards';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon', 'public.worker_is_available_for_shift(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.worker_is_available_for_shift(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE') then
    raise exception 'availability predicate must not be directly callable by API roles';
  end if;
  if has_function_privilege('anon', 'public.accept_shift(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.accept_shift(uuid)', 'EXECUTE') then
    raise exception 'acceptance RPC grants are unsafe';
  end if;
end;
$$;

rollback;
