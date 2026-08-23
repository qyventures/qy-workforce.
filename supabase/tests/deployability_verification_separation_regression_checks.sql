-- Regression checks: deployability must continue to evaluate residency and work eligibility
-- through their independent, expiry-aware evidence helpers while also requiring current consent.

begin;

do $$
declare
  def text;
begin
  select pg_get_functiondef('public.worker_has_deployment_prerequisites(uuid)'::regprocedure) into def;

  if position('worker_has_current_residency' in def)=0 then
    raise exception 'deployability no longer uses current residency evidence';
  end if;

  if position('worker_has_current_work_eligibility' in def)=0 then
    raise exception 'deployability no longer uses current work-eligibility evidence';
  end if;

  if position('worker_has_current_consent' in def)=0
     or position('identity_verification' in def)=0
     or position('work_eligibility' in def)=0
     or position('location_clocking' in def)=0 then
    raise exception 'deployability no longer requires current operational consent versions';
  end if;

  if position('wp.residency_verified' in def)>0
     or position('wp.work_eligibility = ''eligible''' in def)>0 then
    raise exception 'deployability regressed to denormalised residency/work-eligibility profile flags';
  end if;
end $$;

-- The two evidence helpers themselves must remain hardened and expiry-aware.
do $$
declare
  fn regprocedure;
  def text;
begin
  foreach fn in array array[
    'public.worker_has_current_residency(uuid)'::regprocedure,
    'public.worker_has_current_work_eligibility(uuid)'::regprocedure
  ] loop
    select pg_get_functiondef(fn) into def;

    if position('valid_until' in def)=0 or position('now()' in def)=0 then
      raise exception 'verification helper % is not expiry-aware', fn;
    end if;

    if not exists (
      select 1 from pg_proc p
      where p.oid=fn
        and p.prosecdef
        and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=public%'
    ) then
      raise exception 'verification helper % missing SECURITY DEFINER/search_path hardening', fn;
    end if;
  end loop;
end $$;

rollback;
