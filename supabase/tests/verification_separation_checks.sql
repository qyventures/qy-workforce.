-- Verification-boundary regression checks. Run after all migrations in a disposable Supabase/Postgres database.
-- These checks intentionally avoid production credentials and external identity providers.

begin;

do $$
begin
  if to_regclass('public.residency_verifications') is null then
    raise exception 'residency_verifications table missing';
  end if;
  if to_regclass('public.work_eligibility_checks') is null then
    raise exception 'work_eligibility_checks table missing';
  end if;
end $$;

do $$
declare
  v_rls boolean;
begin
  select relrowsecurity into v_rls from pg_class where oid='public.residency_verifications'::regclass;
  if not v_rls then raise exception 'RLS disabled on residency_verifications'; end if;
  select relrowsecurity into v_rls from pg_class where oid='public.work_eligibility_checks'::regclass;
  if not v_rls then raise exception 'RLS disabled on work_eligibility_checks'; end if;
end $$;

do $$
begin
  if has_table_privilege('authenticated','public.residency_verifications','INSERT') then
    raise exception 'authenticated role can insert residency evidence directly';
  end if;
  if has_table_privilege('authenticated','public.residency_verifications','UPDATE') then
    raise exception 'authenticated role can update residency evidence directly';
  end if;
  if has_table_privilege('authenticated','public.work_eligibility_checks','INSERT') then
    raise exception 'authenticated role can insert work eligibility directly';
  end if;
  if has_table_privilege('authenticated','public.work_eligibility_checks','UPDATE') then
    raise exception 'authenticated role can update work eligibility directly';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='record_residency_verification_staging' and p.prosecdef
  ) then raise exception 'secure residency RPC missing'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='record_work_eligibility_staging' and p.prosecdef
  ) then raise exception 'secure eligibility RPC missing'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='worker_has_current_residency' and p.prosecdef
  ) then raise exception 'current residency predicate missing'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='worker_has_current_work_eligibility' and p.prosecdef
  ) then raise exception 'current eligibility predicate missing'; end if;
end $$;

do $$
declare
  v_bad_provider_count integer;
begin
  -- Schema-level allow-lists must make production/unknown provider environments impossible.
  select count(*) into v_bad_provider_count
  from pg_constraint c
  join pg_class t on t.oid=c.conrelid
  join pg_namespace n on n.oid=t.relnamespace
  where n.nspname='public'
    and t.relname in ('residency_verifications','work_eligibility_checks')
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%environment%mock%staging%';
  if v_bad_provider_count < 2 then
    raise exception 'mock/staging environment constraints missing';
  end if;
end $$;

do $$
begin
  -- Public/anon must never execute verification mutation RPCs.
  if has_function_privilege('public',
      'public.record_residency_verification_staging(uuid,text,text,text,text,text,timestamptz)',
      'EXECUTE') then
    raise exception 'public can execute residency verification RPC';
  end if;
  if has_function_privilege('public',
      'public.record_work_eligibility_staging(uuid,text,text,public.eligibility_status,text,timestamptz)',
      'EXECUTE') then
    raise exception 'public can execute eligibility verification RPC';
  end if;
end $$;

rollback;
