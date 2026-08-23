-- Regression checks for worker timesheet submission integrity.

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.submit_timesheet(uuid)'::regprocedure) into v_def;

  if v_def not ilike '%security definer%' then
    raise exception 'submit_timesheet must remain SECURITY DEFINER';
  end if;
  if v_def not ilike '%set search_path = public%' then
    raise exception 'submit_timesheet must pin search_path';
  end if;
  if v_def not ilike '%for update of a%' then
    raise exception 'submit_timesheet must lock the assignment';
  end if;
  if v_def not ilike '%for update%' then
    raise exception 'submit_timesheet must serialize timesheet retries';
  end if;
  if v_def not ilike '%v_status = ''submitted''%' then
    raise exception 'submitted retry must be idempotent';
  end if;
  if v_def not ilike '%v_status in (''approved'',''payroll_ready'')%' then
    raise exception 'approved/payroll-ready states must be terminal to worker submission';
  end if;
  if v_def not ilike '%within_geofence is true%' then
    raise exception 'submission must use geofence-accepted attendance only';
  end if;
  if v_def not ilike '%te.source = ''worker_app''%' then
    raise exception 'submission must bind to worker-app attendance source';
  end if;
  if v_def not ilike '%te.created_by = v_worker%' then
    raise exception 'submission must bind attendance to assignment worker';
  end if;
  if v_def not ilike '%v_minutes > 1440%' then
    raise exception 'submission must keep the 24-hour defensive duration ceiling';
  end if;
end;
$$;

-- Authenticated users may execute the RPC, but direct timesheet mutation remains revoked.
do $$
begin
  if not has_function_privilege('authenticated', 'public.submit_timesheet(uuid)', 'EXECUTE') then
    raise exception 'authenticated role must execute submit_timesheet';
  end if;
  if has_table_privilege('authenticated', 'public.timesheets', 'INSERT')
     or has_table_privilege('authenticated', 'public.timesheets', 'UPDATE')
     or has_table_privilege('authenticated', 'public.timesheets', 'DELETE') then
    raise exception 'authenticated direct timesheet mutation must remain revoked';
  end if;
end;
$$;
