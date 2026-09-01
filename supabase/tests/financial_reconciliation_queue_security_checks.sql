-- Structural security checks for financial reconciliation queue.

do $$
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='financial_reconciliation_cases' and c.relrowsecurity
  ) then raise exception 'financial_reconciliation_cases must have RLS enabled'; end if;

  if has_table_privilege('authenticated','public.financial_reconciliation_cases','INSERT')
     or has_table_privilege('authenticated','public.financial_reconciliation_cases','UPDATE')
     or has_table_privilege('authenticated','public.financial_reconciliation_cases','DELETE') then
    raise exception 'authenticated must not directly mutate reconciliation cases';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='sync_financial_reconciliation_cases' and p.prosecdef
  ) then raise exception 'sync_financial_reconciliation_cases must be security definer'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='transition_financial_reconciliation_case' and p.prosecdef
  ) then raise exception 'transition_financial_reconciliation_case must be security definer'; end if;

  if not exists (
    select 1 from pg_constraint where conrelid='public.financial_reconciliation_cases'::regclass
      and contype='u'
  ) then raise exception 'reconciliation cases require deduplication constraint'; end if;
end $$;

-- The reconciliation workflow must remain advisory/corrective workflow only.
-- It must not mutate immutable financial snapshots.
do $$
declare src text;
begin
  select pg_get_functiondef('public.sync_financial_reconciliation_cases(date,date)'::regprocedure) into src;
  if src ~* 'update[[:space:]]+public\.(timesheets|payroll_batch_items|worker_payouts|client_billing_items)'
     or src ~* 'delete[[:space:]]+from[[:space:]]+public\.(timesheets|payroll_batch_items|worker_payouts|client_billing_items)' then
    raise exception 'reconciliation sync must not mutate source financial ledgers';
  end if;
end $$;
