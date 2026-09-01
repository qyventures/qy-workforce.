-- Structural regression checks for payroll payout and adjustment controls.
do $$
declare
  v_def text;
  v_direct boolean;
  v_anon boolean;
begin
  if to_regclass('public.payroll_adjustments') is null then raise exception 'payroll adjustments missing'; end if;
  if to_regclass('public.worker_payouts') is null then raise exception 'worker payouts missing'; end if;

  if not (select relrowsecurity from pg_class where oid='public.payroll_adjustments'::regclass) then raise exception 'payroll adjustments RLS missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.worker_payouts'::regclass) then raise exception 'worker payouts RLS missing'; end if;

  select has_table_privilege('authenticated','public.payroll_adjustments','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct adjustment mutation must remain denied'; end if;
  select has_table_privilege('authenticated','public.worker_payouts','INSERT,UPDATE,DELETE') into v_direct;
  if v_direct then raise exception 'authenticated direct payout mutation must remain denied'; end if;

  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='prepare_worker_payouts';
  if v_def is null then raise exception 'prepare payout RPC missing'; end if;
  if position('security definer' in lower(v_def))=0 then raise exception 'prepare payout RPC must be SECURITY DEFINER'; end if;
  if position('status in (''locked'',''exported'')' in replace(lower(v_def),' ',''))=0
     and position('locked' in lower(v_def))=0 then raise exception 'locked payroll batch guard missing'; end if;

  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='set_worker_payout_status';
  if v_def is null then raise exception 'payout transition RPC missing'; end if;
  if position('invalid payout transition' in v_def)=0 then raise exception 'payout state transition guard missing'; end if;
  if position('cash exception requires reason' in v_def)=0 then raise exception 'cash-paid exception reason guard missing'; end if;
  if position('worker_payout.status_changed' in v_def)=0 then raise exception 'payout audit event missing'; end if;

  select has_function_privilege('anon','public.set_worker_payout_status(uuid,text,text,text,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not mutate payout status'; end if;
  select has_function_privilege('anon','public.add_payroll_adjustment(uuid,text,numeric,text)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not create payroll adjustments'; end if;

  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='worker_payouts' and column_name='payable_amount' and is_generated='ALWAYS') then
    raise exception 'payable amount must remain database-generated';
  end if;
end;
$$;
