-- Regression/security checks for serialized payroll batch creation.

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.create_payroll_batch(date,date)'::regprocedure)
    into v_def;

  if v_def not ilike '%security definer%' then
    raise exception 'create_payroll_batch must remain SECURITY DEFINER';
  end if;
  if v_def not ilike '%set search_path%public%' then
    raise exception 'create_payroll_batch must pin search_path';
  end if;
  if v_def not ilike '%pg_advisory_xact_lock%' then
    raise exception 'create_payroll_batch must serialize concurrent batch construction';
  end if;
  if v_def not ilike '%payroll-batch-create%' then
    raise exception 'expected stable payroll batch advisory lock key';
  end if;
  if v_def not ilike '%pb.status <> ''cancelled''%' then
    raise exception 'active payroll workflow exclusion must remain enforced';
  end if;
  if v_def not ilike '%t.status = ''approved''%' then
    raise exception 'only approved timesheets may enter a new payroll batch';
  end if;
end;
$$;

-- Authenticated callers may invoke the RPC, while application-role checks inside
-- the SECURITY DEFINER function limit execution to finance/admin.
do $$
begin
  if not has_function_privilege('authenticated', 'public.create_payroll_batch(date,date)', 'EXECUTE') then
    raise exception 'authenticated must retain execute privilege on create_payroll_batch';
  end if;
  if has_function_privilege('anon', 'public.create_payroll_batch(date,date)', 'EXECUTE') then
    raise exception 'anon must not execute create_payroll_batch';
  end if;
end;
$$;
