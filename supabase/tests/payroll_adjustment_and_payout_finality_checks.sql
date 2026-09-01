-- Structural regression checks for adjustment segregation and payroll finality.
begin;

do $$
declare v_def text;
begin
  if exists (
    select 1 from unnest(array['public.payroll_adjustments','public.worker_payouts']) t(name)
    where has_table_privilege('authenticated', t.name, 'INSERT,UPDATE,DELETE')
       or has_table_privilege('anon', t.name, 'INSERT,UPDATE,DELETE')
  ) then raise exception 'API roles must not mutate adjustments or payouts directly'; end if;

  if not exists (select 1 from pg_constraint where conrelid='public.payroll_adjustments'::regclass and conname='payroll_adjustments_independent_review_check')
     or not exists (select 1 from pg_constraint where conrelid='public.payroll_adjustments'::regclass and conname='payroll_adjustments_review_state_check') then
    raise exception 'adjustments require independent, timestamped reviews';
  end if;

  select pg_get_functiondef('public.add_payroll_adjustment(uuid,text,numeric,text)'::regprocedure) into v_def;
  if v_def not ilike '%pb.status = ''locked''%' or v_def not ilike '%unexported payroll batch%' then
    raise exception 'adjustments must be created only for locked, unexported batches';
  end if;

  select pg_get_functiondef('public.review_payroll_adjustment(uuid,boolean)'::regprocedure) into v_def;
  if v_def not ilike '%for update of pa, pb%'
     or v_def not ilike '%self review is not permitted%'
     or v_def not ilike '%v_batch_status <> ''locked''%'
     or v_def not ilike '%non-pending payout%' then
    raise exception 'adjustment reviews must lock, segregate duties, and preserve exported/payment finality';
  end if;

  select pg_get_functiondef('public.prepare_worker_payouts(uuid)'::regprocedure) into v_def;
  if v_def not ilike '%status=''locked''%'
     or v_def ilike '%''locked'',''exported''%' then
    raise exception 'payout preparation must not run after export';
  end if;

  select pg_get_functiondef('public.record_payroll_export(uuid,text,text,integer)'::regprocedure) into v_def;
  if v_def not ilike '%all payroll payouts must be prepared before export%'
     or v_def not ilike '%pending payroll adjustments must be resolved before export%'
     or v_def not ilike '%for update%' then
    raise exception 'export must lock and require finalized payroll payout inputs';
  end if;

  select pg_get_functiondef('public.set_worker_payout_status(uuid,text,text,text,text)'::regprocedure) into v_def;
  if v_def not ilike '%paid payout requires external reference%'
     or v_def not ilike '%external_reference_present%' then
    raise exception 'paid payouts require a traceable reference and an audit-safe presence flag';
  end if;

  if has_function_privilege('anon','public.review_payroll_adjustment(uuid,boolean)','EXECUTE')
     or has_function_privilege('anon','public.prepare_worker_payouts(uuid)','EXECUTE')
     or has_function_privilege('anon','public.set_worker_payout_status(uuid,text,text,text,text)','EXECUTE') then
    raise exception 'anon must not invoke payroll adjustment or payout RPCs';
  end if;
end;
$$;

rollback;
