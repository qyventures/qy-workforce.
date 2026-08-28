-- Structural regression checks for single-batch payroll membership and audited release.
do $$
declare
  v_create text;
  v_lock text;
  v_cancel text;
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'payroll_batch_items'
      and indexname = 'uq_payroll_batch_items_timesheet'
      and indexdef ilike 'create unique index%timesheet_id%'
  ) then
    raise exception 'timesheets must have globally unique payroll batch membership';
  end if;

  if has_table_privilege('authenticated', 'public.payroll_batches', 'INSERT')
     or has_table_privilege('authenticated', 'public.payroll_batches', 'UPDATE')
     or has_table_privilege('authenticated', 'public.payroll_batches', 'DELETE')
     or has_table_privilege('authenticated', 'public.payroll_batch_items', 'INSERT')
     or has_table_privilege('authenticated', 'public.payroll_batch_items', 'UPDATE')
     or has_table_privilege('authenticated', 'public.payroll_batch_items', 'DELETE') then
    raise exception 'authenticated payroll mutations must be RPC-only';
  end if;

  select pg_get_functiondef('public.create_payroll_batch(date,date)'::regprocedure) into v_create;
  select pg_get_functiondef('public.lock_payroll_batch(uuid)'::regprocedure) into v_lock;
  select pg_get_functiondef('public.cancel_payroll_batch(uuid,text)'::regprocedure) into v_cancel;

  if v_create not ilike '%on conflict (timesheet_id) do nothing%' then
    raise exception 'batch creation must safely skip already-batched timesheets';
  end if;
  if v_lock not ilike '%for update%'
     or v_lock not ilike '%empty payroll batch cannot be locked%'
     or v_lock not ilike '%t.status <> ''approved''%' then
    raise exception 'batch locking must serialize and revalidate approved non-empty membership';
  end if;
  if v_cancel not ilike '%only a draft payroll batch can be cancelled%'
     or v_cancel not ilike '%delete from public.payroll_batch_items%'
     or v_cancel not ilike '%payroll_batch.cancelled%' then
    raise exception 'draft cancellation must release membership and write an audit event';
  end if;

  if has_function_privilege('anon', 'public.cancel_payroll_batch(uuid,text)', 'EXECUTE')
     or has_function_privilege('public', 'public.cancel_payroll_batch(uuid,text)', 'EXECUTE') then
    raise exception 'anonymous roles must not cancel payroll batches';
  end if;
  if not has_function_privilege('authenticated', 'public.cancel_payroll_batch(uuid,text)', 'EXECUTE') then
    raise exception 'authenticated Finance/Admin callers need payroll cancellation RPC execution';
  end if;
end $$;
