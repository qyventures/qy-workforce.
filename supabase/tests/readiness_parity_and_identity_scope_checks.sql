-- Structural regression checks for live readiness parity and minimized identity scopes.
begin;

do $$
declare
  v_start text;
  v_readiness text;
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.identity_provider_sessions'::regclass
      and conname='identity_provider_sessions_minimum_scope_check'
  ) then
    raise exception 'identity sessions require a minimum-scope constraint';
  end if;

  select pg_get_functiondef('public.start_identity_session(text,text,text,text,text[])'::regprocedure)
    into v_start;
  if v_start is null
     or v_start not ilike '%p_requested_scopes is distinct from array[''openid'']::text[]%'
     or v_start not ilike '%only the openid identity scope is permitted%'
     or v_start not ilike '%array[''openid'']::text[]%'
     or v_start not ilike '%scope_contract%' then
    raise exception 'identity session start must enforce and record the minimum scope contract';
  end if;

  select pg_get_functiondef('public.get_worker_readiness()'::regprocedure)
    into v_readiness;
  if v_readiness is null
     or v_readiness not ilike '%public.worker_has_deployment_prerequisites(auth.uid())%'
     or v_readiness not ilike '%wr.approved and r.active%'
     or v_readiness not ilike '%wt.status=''passed'' and (wt.expires_at is null or wt.expires_at > now())%' then
    raise exception 'worker readiness must use the live deployment predicate and current role/training state';
  end if;

  if has_function_privilege('anon', 'public.get_worker_readiness()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_worker_readiness()', 'EXECUTE')
     or has_function_privilege('anon', 'public.start_identity_session(text,text,text,text,text[])', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.start_identity_session(text,text,text,text,text[])', 'EXECUTE') then
    raise exception 'readiness and identity-session RPC grants are unsafe';
  end if;
end;
$$;

rollback;
