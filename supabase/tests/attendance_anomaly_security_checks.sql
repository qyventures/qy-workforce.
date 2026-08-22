-- Static/security regression checks for attendance anomaly review controls.

begin;

do $$
declare
  v_trigger_def text;
  v_review_def text;
  v_rls boolean;
begin
  select c.relrowsecurity into v_rls
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='attendance_anomalies';
  if v_rls is distinct from true then raise exception 'attendance_anomalies must have RLS enabled'; end if;

  select pg_get_functiondef(p.oid) into v_trigger_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='detect_attendance_anomalies';
  if v_trigger_def is null then raise exception 'attendance anomaly detector missing'; end if;
  if position('SECURITY DEFINER' in upper(v_trigger_def))=0 then raise exception 'detector must be security definer'; end if;
  if position('device_fingerprint_hash' in v_trigger_def)=0 then raise exception 'device reuse signal missing'; end if;
  if position('12 hours' in v_trigger_def)=0 then raise exception 'device reuse window missing'; end if;
  if position('80_to_100_percent_radius' in v_trigger_def)=0 then raise exception 'geofence-edge signal missing'; end if;
  if position('attendance.anomaly_created' in v_trigger_def)=0 then raise exception 'anomaly creation must be audited'; end if;

  select pg_get_functiondef(p.oid) into v_review_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='review_attendance_anomaly';
  if v_review_def is null then raise exception 'attendance anomaly review RPC missing'; end if;
  if position('public.is_ops()' in v_review_def)=0 then raise exception 'review RPC must require ops role'; end if;
  if position('attendance.anomaly_reviewed' in v_review_def)=0 then raise exception 'review outcome must be audited'; end if;
  if position('500' in v_review_def)=0 then raise exception 'review notes must be bounded'; end if;
end $$;

-- Workers must not receive a direct read policy on anomaly records.
do $$
begin
  if exists(
    select 1 from pg_policies
    where schemaname='public' and tablename='attendance_anomalies'
      and lower(policyname) like '%worker%'
  ) then raise exception 'worker policy must not expose attendance anomalies'; end if;
end $$;

rollback;
