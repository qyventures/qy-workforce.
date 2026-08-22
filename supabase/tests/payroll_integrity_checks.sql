-- QY Workforce payroll integrity invariants.
-- Intended for staging/CI after migrations have been applied.

begin;

do $$
begin
  if has_table_privilege('authenticated','public.payroll_batches','INSERT')
     or has_table_privilege('authenticated','public.payroll_batches','UPDATE')
     or has_table_privilege('authenticated','public.payroll_batches','DELETE') then
    raise exception 'payroll batch mutations must be RPC-only';
  end if;

  if has_table_privilege('authenticated','public.payroll_batch_items','INSERT')
     or has_table_privilege('authenticated','public.payroll_batch_items','UPDATE')
     or has_table_privilege('authenticated','public.payroll_batch_items','DELETE') then
    raise exception 'payroll item mutations must be RPC-only';
  end if;

  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='payroll_batch_items'
      and t.tgname='payroll_batch_items_guard_mutation' and not t.tgisinternal
  ) then raise exception 'payroll membership immutability trigger required'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('create_payroll_batch','lock_payroll_batch','record_payroll_export','cancel_payroll_batch')
      and not p.prosecdef
  ) then raise exception 'payroll mutation RPCs must remain SECURITY DEFINER'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='create_payroll_batch'
      and pg_get_functiondef(p.oid) ilike '%pb.status <> ''cancelled''%'
  ) then raise exception 'active payroll workflows must not duplicate a timesheet'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='lock_payroll_batch'
      and pg_get_functiondef(p.oid) ilike '%for update%'
      and pg_get_functiondef(p.oid) ilike '%cannot lock empty payroll batch%'
      and pg_get_functiondef(p.oid) ilike '%timesheets no longer approved%'
  ) then raise exception 'payroll lock must serialize and validate member timesheets'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='record_payroll_export'
      and pg_get_functiondef(p.oid) ilike '%sha256 checksum required%'
      and pg_get_functiondef(p.oid) ilike '%export count does not match locked batch%'
      and pg_get_functiondef(p.oid) ilike '%export evidence is immutable%'
  ) then raise exception 'payroll export evidence must be reconciled and immutable'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='payroll_batches' and column_name='locked_by'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='payroll_batches' and column_name='exported_by'
  ) then raise exception 'payroll lock/export actor attribution required'; end if;
end $$;

rollback;
