-- QY Workforce retention-enforcement security invariants.
-- Intended for staging/CI after all migrations are applied.

do $$
declare
  v_def text;
  v_rls boolean;
  v_days integer;
  v_auth_exec boolean;
  v_anon_exec boolean;
begin
  select p.prosecdef, pg_get_functiondef(p.oid)
    into strict v_rls, v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='run_retention_maintenance'
    and pg_get_function_identity_arguments(p.oid)='p_execute boolean, p_batch_limit integer';

  if not v_rls then raise exception 'run_retention_maintenance must be SECURITY DEFINER'; end if;
  if position('retention_hold=true' in replace(v_def,' ',''))=0 then
    raise exception 'retention maintenance must honour worker retention holds';
  end if;
  if position('latitude=null' in replace(v_def,' ',''))=0 or position('device_fingerprint_hash=null' in replace(v_def,' ',''))=0 then
    raise exception 'location retention must minimise precise coordinates/device hashes rather than remove attendance chronology';
  end if;
  if position('provider_subject_hash=null' in replace(v_def,' ',''))=0 then
    raise exception 'identity retention must remove provider subject correlation';
  end if;
  if position("verified_attributes - 'identity_verified' - 'residency_verified' - 'work_eligibility'" in v_def)=0 then
    raise exception 'identity minimisation must be idempotent once only approved normalized fields remain';
  end if;
  if position('audit_events' in v_def)=0 or position('payroll_and_timesheets' in v_def)=0 then
    raise exception 'manual/legal-review retention classes must remain explicit';
  end if;
  if position('v_role <> ''admin''' in v_def)=0 or position('service_role' in v_def)=0 then
    raise exception 'destructive retention execution must remain Admin/service-role restricted';
  end if;
  if position('least(coalesce(p_batch_limit,500),5000)' in replace(v_def,' ',''))=0 then
    raise exception 'retention execution must remain batch-capped';
  end if;

  select relrowsecurity into v_rls
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='retention_runs';
  if not coalesce(v_rls,false) then raise exception 'retention_runs must have RLS enabled'; end if;

  if has_table_privilege('authenticated','public.retention_runs','INSERT')
     or has_table_privilege('authenticated','public.retention_runs','UPDATE')
     or has_table_privilege('authenticated','public.retention_runs','DELETE') then
    raise exception 'authenticated clients must not mutate retention run evidence directly';
  end if;

  select retention_days into v_days
  from public.data_retention_policies where data_class='identity_sessions';
  if v_days is null or v_days > 30 then
    raise exception 'identity session retention must be configured at 30 days or less';
  end if;

  select has_function_privilege('authenticated','public.run_retention_maintenance(boolean,integer)','EXECUTE') into v_auth_exec;
  select has_function_privilege('anon','public.run_retention_maintenance(boolean,integer)','EXECUTE') into v_anon_exec;
  if not v_auth_exec then raise exception 'authenticated Admin/Auditor callers need RPC access for role-checked preview/execution'; end if;
  if v_anon_exec then raise exception 'anonymous users must never execute retention maintenance'; end if;
end;
$$;
