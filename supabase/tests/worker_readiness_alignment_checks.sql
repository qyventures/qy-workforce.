-- Regression checks: the worker-facing readiness RPC must remain aligned with
-- the authoritative, expiry-aware deployment controls.

begin;

do $$
declare
  fn regprocedure := 'public.get_worker_readiness()'::regprocedure;
  def text;
begin
  select pg_get_functiondef(fn) into def;

  if position('worker_has_current_residency' in def)=0 then
    raise exception 'worker readiness no longer uses current residency evidence';
  end if;

  if position('worker_has_current_work_eligibility' in def)=0 then
    raise exception 'worker readiness no longer uses current work-eligibility evidence';
  end if;

  if position('worker_has_deployment_prerequisites' in def)=0 then
    raise exception 'worker readiness deployable flag is not authoritative';
  end if;

  if position('worker_has_current_consent' in def)=0
     or position('identity_verification' in def)=0
     or position('work_eligibility' in def)=0
     or position('location_clocking' in def)=0 then
    raise exception 'worker readiness does not use current required consent versions';
  end if;

  if position('wt.expires_at' in def)=0 or position('wt.expires_at > now()' in def)=0 then
    raise exception 'worker readiness training count is not expiry-aware';
  end if;

  if position('r.active = true' in def)=0 then
    raise exception 'worker readiness counts inactive role approvals';
  end if;

  if not exists (
    select 1
    from pg_proc p
    where p.oid = fn
      and p.prosecdef
      and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=public%'
  ) then
    raise exception 'get_worker_readiness missing SECURITY DEFINER/search_path hardening';
  end if;
end $$;

-- Public/anonymous callers must not inherit execution through PUBLIC.
do $$
begin
  if has_function_privilege('public','public.get_worker_readiness()','EXECUTE') then
    raise exception 'PUBLIC must not execute get_worker_readiness';
  end if;

  if not has_function_privilege('authenticated','public.get_worker_readiness()','EXECUTE') then
    raise exception 'authenticated workers need get_worker_readiness execute privilege';
  end if;
end $$;

rollback;
