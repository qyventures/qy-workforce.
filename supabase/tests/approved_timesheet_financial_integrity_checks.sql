-- Regression checks for approved/payroll-ready timesheet financial immutability.

do $$
declare
  v_trigger_count integer;
  v_function_security text;
begin
  select count(*) into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname='timesheets'
    and t.tgname='timesheets_guard_approved_financial_basis'
    and not t.tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'expected approved timesheet financial guard trigger';
  end if;

  select prosecdef::text into v_function_security
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='guard_approved_timesheet_financial_basis'
  limit 1;

  if v_function_security is null then
    raise exception 'approved timesheet guard function missing';
  end if;

  if v_function_security <> 'false' then
    raise exception 'approved timesheet guard must not be SECURITY DEFINER';
  end if;
end;
$$;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='guard_approved_timesheet_financial_basis'
  limit 1;

  if v_def not ilike '%old.status%approved%'
     or v_def not ilike '%payroll_ready%'
     or v_def not ilike '%assignment_id%'
     or v_def not ilike '%payable_minutes%'
     or v_def not ilike '%worker_amount%'
     or v_def not ilike '%client_amount%' then
    raise exception 'approved timesheet guard no longer protects the full financial basis';
  end if;
end;
$$;
