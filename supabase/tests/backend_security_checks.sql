-- QY Workforce backend security invariants.
-- Intended for staging/CI after migrations have been applied.

begin;

do $$
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='identity_provider_sessions' and c.relrowsecurity) then
    raise exception 'identity_provider_sessions must have RLS enabled';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='identity_provider_sessions'
      and column_name in ('access_token','refresh_token','id_token','raw_payload','nric','uinfin')
  ) then raise exception 'identity provider sessions must not store raw tokens or national identifiers'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='worker_profiles' and column_name='identity_verified'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='worker_profiles' and column_name='residency_verified'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='worker_profiles' and column_name='work_eligibility'
  ) then raise exception 'identity, residency and work eligibility must remain distinct'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('start_identity_session','complete_identity_verification_staging','get_site_margin_report')
      and not p.prosecdef
  ) then raise exception 'security boundary RPC must remain security definer'; end if;

  if not exists (
    select 1 from public.data_retention_policies where data_class='identity_verifications'
  ) then raise exception 'identity verification retention policy required'; end if;
end $$;

rollback;
