-- Regression checks for high-severity attendance anomaly gating at timesheet approval.

do $$
declare
  v_def text;
  v_prosecdef boolean;
  v_config text[];
begin
  select pg_get_functiondef(p.oid), p.prosecdef, p.proconfig
    into v_def, v_prosecdef, v_config
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='review_timesheet'
    and pg_get_function_identity_arguments(p.oid)='p_timesheet_id uuid, p_decision text, p_rejection_reason text';

  if v_def is null then raise exception 'review_timesheet function missing'; end if;
  if not v_prosecdef then raise exception 'review_timesheet must remain SECURITY DEFINER'; end if;
  if not ('search_path=public'=any(v_config)) then raise exception 'review_timesheet must pin search_path'; end if;

  if position('attendance_anomalies' in v_def)=0 then
    raise exception 'review_timesheet must inspect attendance anomalies';
  end if;
  if position("aa.severity='high'" in v_def)=0 then
    raise exception 'approval gate must be limited to high-severity anomalies';
  end if;
  if position("aa.status='open'" in v_def)=0 then
    raise exception 'open high-severity anomalies must block approval';
  end if;
  if position("aa.status='confirmed'" in v_def)=0 then
    raise exception 'confirmed high-severity anomalies must block approval';
  end if;
  if position("p_decision='approve'" in v_def)=0 then
    raise exception 'anomaly gate must apply at approval boundary';
  end if;
  if position('rejection reason required' in v_def)=0 then
    raise exception 'rejection path must remain available with rationale';
  end if;
  if position('high_severity_anomaly_gate_checked' in v_def)=0 then
    raise exception 'approval audit must record anomaly-gate execution';
  end if;
end $$;

-- Authenticated callers may use only the controlled RPC; direct anomaly mutation stays revoked.
do $$
begin
  if not has_function_privilege('authenticated','public.review_timesheet(uuid,text,text)','EXECUTE') then
    raise exception 'authenticated role needs review_timesheet execute';
  end if;
  if has_table_privilege('authenticated','public.attendance_anomalies','UPDATE') then
    raise exception 'authenticated role must not directly update attendance anomalies';
  end if;
end $$;
