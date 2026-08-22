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
    where n.nspname='public' and p.proname in (
      'start_identity_session','complete_identity_verification_staging','get_site_margin_report',
      'create_shift_draft','open_shift','mark_identity_callback_received_staging',
      'fail_identity_session_staging','expire_identity_sessions','review_timesheet',
      'request_privacy_action','review_privacy_request','get_attendance_exception_queue'
    ) and not p.prosecdef
  ) then raise exception 'security boundary RPC must remain security definer'; end if;

  if not exists (select 1 from public.data_retention_policies where data_class='identity_verifications') then
    raise exception 'identity verification retention policy required';
  end if;
  if not exists (select 1 from public.data_retention_policies where data_class='privacy_requests') then
    raise exception 'privacy request retention policy required';
  end if;

  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('clients','sites','roles','shifts') and not c.relrowsecurity
  ) then raise exception 'demand configuration tables must have RLS enabled'; end if;

  if not exists (select 1 from information_schema.routines where routine_schema='public' and routine_name='create_shift_draft') then
    raise exception 'secure create_shift_draft RPC required';
  end if;
  if not exists (select 1 from information_schema.routines where routine_schema='public' and routine_name='open_shift') then
    raise exception 'audited open_shift RPC required';
  end if;

  if has_table_privilege('authenticated', 'public.shifts', 'INSERT')
     or has_table_privilege('authenticated', 'public.shifts', 'UPDATE')
     or has_table_privilege('authenticated', 'public.shifts', 'DELETE') then
    raise exception 'authenticated role must not have direct shift write privileges';
  end if;
  if has_table_privilege('authenticated', 'public.time_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.time_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.time_events', 'DELETE') then
    raise exception 'authenticated role must not have direct attendance mutation privileges';
  end if;
  if has_table_privilege('authenticated', 'public.timesheets', 'INSERT')
     or has_table_privilege('authenticated', 'public.timesheets', 'UPDATE')
     or has_table_privilege('authenticated', 'public.timesheets', 'DELETE') then
    raise exception 'authenticated role must not have direct timesheet mutation privileges';
  end if;
  if has_table_privilege('authenticated', 'public.site_margin_summary', 'SELECT') then
    raise exception 'authenticated role must not read full site margin view directly';
  end if;

  if not exists (
    select 1 from pg_indexes where schemaname='public' and tablename='identity_provider_sessions'
      and indexname='uq_identity_provider_sessions_active'
  ) then raise exception 'active identity sessions must be uniquely constrained'; end if;

  if not exists (select 1 from information_schema.routines where routine_schema='public' and routine_name='expire_identity_sessions') then
    raise exception 'identity session expiry RPC required';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_timesheet'
      and pg_get_functiondef(p.oid) ilike '%for update of t%'
      and pg_get_functiondef(p.oid) ilike '%self review is not permitted%'
  ) then raise exception 'timesheet review must lock the row and enforce separation of duties'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_attendance_exception_queue'
      and p.prosecdef
      and pg_get_functiondef(p.oid) ilike '%Worker #%'
      and pg_get_functiondef(p.oid) not ilike '%display_name%'
      and pg_get_functiondef(p.oid) ilike '%supervisor_sites%'
  ) then raise exception 'attendance exception queue must be scoped and pseudonymous'; end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='privacy_requests' and c.relrowsecurity
  ) then raise exception 'privacy_requests must have RLS enabled'; end if;

  if has_table_privilege('authenticated', 'public.privacy_requests', 'INSERT')
     or has_table_privilege('authenticated', 'public.privacy_requests', 'UPDATE')
     or has_table_privilege('authenticated', 'public.privacy_requests', 'DELETE') then
    raise exception 'privacy request writes must be RPC-only';
  end if;

  if not exists (
    select 1 from pg_indexes where schemaname='public' and tablename='privacy_requests'
      and indexname='privacy_requests_one_open_per_type'
  ) then raise exception 'duplicate active privacy requests must be constrained'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_privacy_request'
      and pg_get_functiondef(p.oid) ilike '%for update%'
      and pg_get_functiondef(p.oid) ilike '%self-review is not permitted%'
      and pg_get_functiondef(p.oid) ilike '%retention hold%'
  ) then raise exception 'privacy review must lock rows, block self-review and respect retention holds'; end if;
end $$;

rollback;
