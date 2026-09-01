-- Structural regression checks for dual-control payout operations.
do $$
declare v_def text; v_anon boolean;
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='worker_payouts' and column_name='prepared_by') then
    raise exception 'payout preparer attribution missing';
  end if;

  select pg_get_functiondef('public.review_payroll_adjustment(uuid,boolean)'::regprocedure) into v_def;
  if position('self review is not permitted' in v_def)=0 then raise exception 'adjustment dual control missing'; end if;
  if position('adjustment inputs are frozen' in v_def)=0 then raise exception 'adjustment freeze missing'; end if;

  select pg_get_functiondef('public.prepare_worker_payouts(uuid)'::regprocedure) into v_def;
  if position('pending adjustments must be reviewed' in v_def)=0 then raise exception 'pending adjustment guard missing'; end if;
  if position('prepared_by' in v_def)=0 then raise exception 'payout preparer attribution missing from RPC'; end if;

  select pg_get_functiondef('public.set_worker_payout_status(uuid,text,text,text,text)'::regprocedure) into v_def;
  if position('payout preparer cannot approve' in v_def)=0 then raise exception 'payout dual control missing'; end if;

  select has_function_privilege('anon','public.get_worker_payout_control_queue(uuid)','EXECUTE') into v_anon;
  if v_anon then raise exception 'anon must not read payout control queue'; end if;
  if not has_function_privilege('authenticated','public.get_worker_payout_control_queue(uuid)','EXECUTE') then
    raise exception 'authenticated role needs payout queue RPC boundary';
  end if;

  select pg_get_functiondef('public.get_worker_payout_control_queue(uuid)'::regprocedure) into v_def;
  if position('auditor' in v_def)=0 or position('md5(sa.worker_id::text)' in v_def)=0 then
    raise exception 'payout queue must remain role-scoped and pseudonymised';
  end if;
end $$;
