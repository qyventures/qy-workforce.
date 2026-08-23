-- Security/regression checks for consent version integrity.

begin;

-- Registry must enforce at most one current version per purpose.
do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname='public'
      and tablename='consent_policy_versions'
      and indexname='consent_policy_one_current_per_purpose'
  ) then raise exception 'missing unique current-consent-policy index'; end if;
end $$;

-- Worker direct writes must be closed; grants and withdrawals go through audited RPCs.
do $$
begin
  if has_table_privilege('authenticated','public.worker_consents','INSERT')
     or has_table_privilege('authenticated','public.worker_consents','UPDATE')
     or has_table_privilege('authenticated','public.worker_consents','DELETE') then
    raise exception 'authenticated retains direct worker_consents write privilege';
  end if;

  if not has_function_privilege('authenticated','public.grant_worker_consent(text,text)','EXECUTE') then
    raise exception 'authenticated cannot execute grant_worker_consent';
  end if;

  if not has_function_privilege('authenticated','public.withdraw_worker_consent(text)','EXECUTE') then
    raise exception 'authenticated cannot execute withdraw_worker_consent';
  end if;
end $$;

-- SECURITY DEFINER functions must pin search_path.
do $$
declare
  fn regprocedure;
begin
  foreach fn in array array[
    'public.grant_worker_consent(text,text)'::regprocedure,
    'public.withdraw_worker_consent(text)'::regprocedure,
    'public.worker_has_current_consent(uuid,text)'::regprocedure,
    'public.worker_has_deployment_prerequisites(uuid)'::regprocedure
  ] loop
    if not exists (
      select 1 from pg_proc p
      where p.oid=fn and p.prosecdef
        and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=public%'
    ) then raise exception 'function % missing SECURITY DEFINER/search_path hardening', fn; end if;
  end loop;
end $$;

-- Deployability must require current-version consent for all three operational purposes.
do $$
declare
  def text;
begin
  select pg_get_functiondef('public.worker_has_deployment_prerequisites(uuid)'::regprocedure) into def;
  if position('worker_has_current_consent' in def)=0
     or position('identity_verification' in def)=0
     or position('work_eligibility' in def)=0
     or position('location_clocking' in def)=0 then
    raise exception 'deployability predicate is not bound to current required consents';
  end if;
end $$;

-- Grant/withdraw RPCs must emit audit events and use server-owned timestamps/source.
do $$
declare
  grant_def text;
  withdraw_def text;
begin
  select pg_get_functiondef('public.grant_worker_consent(text,text)'::regprocedure) into grant_def;
  select pg_get_functiondef('public.withdraw_worker_consent(text)'::regprocedure) into withdraw_def;

  if position('consent.granted' in grant_def)=0
     or position("'worker_app'" in grant_def)=0
     or position('now()' in grant_def)=0 then
    raise exception 'grant_worker_consent missing audit/server-owned fields';
  end if;

  if position('consent.withdrawn' in withdraw_def)=0
     or position('withdrawn_at = now()' in withdraw_def)=0 then
    raise exception 'withdraw_worker_consent missing immediate withdrawal/audit behavior';
  end if;
end $$;

rollback;
