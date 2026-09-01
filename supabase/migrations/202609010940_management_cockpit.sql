-- QY Workforce management cockpit.
-- Deterministic operational/financial indicators only; no recommendation here mutates workflow state.

create or replace function public.get_management_cockpit(
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('ops_manager','finance','admin','auditor') then
    raise exception 'not authorised';
  end if;
  if p_as_of is null then raise exception 'as-of timestamp required'; end if;

  with upcoming as (
    select sh.id, sh.starts_at, sh.ends_at, sh.headcount,
           count(sa.id) filter (where sa.cancelled_at is null) as filled
      from public.shifts sh
      left join public.shift_assignments sa on sa.shift_id=sh.id
     where sh.status in ('open','assigned')
       and sh.starts_at >= p_as_of
       and sh.starts_at < p_as_of + interval '7 days'
     group by sh.id
  ),
  live as (
    select sh.id, sh.headcount,
           count(sa.id) filter (where sa.cancelled_at is null) as filled
      from public.shifts sh
      left join public.shift_assignments sa on sa.shift_id=sh.id
     where sh.status in ('open','assigned')
       and sh.starts_at <= p_as_of
       and sh.ends_at > p_as_of
     group by sh.id
  ),
  latest_clock as (
    select distinct on (te.assignment_id)
           te.assignment_id, te.event_type, te.occurred_at
      from public.time_events te
     where te.event_type in ('clock_in','clock_out')
       and te.occurred_at >= p_as_of - interval '24 hours'
       and te.occurred_at <= p_as_of
     order by te.assignment_id,te.occurred_at desc,te.created_at desc
  ),
  checked_in as (
    select count(*)::bigint as n
      from latest_clock lc
      join public.shift_assignments sa on sa.id=lc.assignment_id and sa.cancelled_at is null
      join public.shifts sh on sh.id=sa.shift_id
     where lc.event_type='clock_in' and sh.starts_at <= p_as_of and sh.ends_at > p_as_of
  ),
  payroll as (
    select
      count(*) filter (where t.status='submitted')::bigint submitted_count,
      count(*) filter (where t.status='approved')::bigint approved_count,
      coalesce(sum(t.worker_amount) filter (where t.status='approved'),0)::numeric approved_exposure
      from public.timesheets t
  ),
  locked_payroll as (
    select coalesce(sum(pbi.gross_pay),0)::numeric amount
      from public.payroll_batch_items pbi
      join public.payroll_batches pb on pb.id=pbi.payroll_batch_id
     where pb.status='locked'
  ),
  billing as (
    select
      count(*) filter (where b.billing_status='pending')::bigint pending_count,
      count(*) filter (where b.billing_status='invoice_ready')::bigint invoice_ready_count,
      count(*) filter (where b.billing_status='disputed')::bigint disputed_count,
      coalesce(sum(b.client_amount) filter (where b.service_date >= date_trunc('month',p_as_of)::date and b.service_date <= p_as_of::date),0)::numeric month_revenue,
      coalesce(sum(b.gross_margin) filter (where b.service_date >= date_trunc('month',p_as_of)::date and b.service_date <= p_as_of::date),0)::numeric month_margin
      from public.client_billing_items b
  )
  select jsonb_build_object(
    'as_of',p_as_of,
    'active_jobs',(select count(*) from live),
    'active_required_headcount',(select coalesce(sum(headcount),0) from live),
    'active_filled_headcount',(select coalesce(sum(filled),0) from live),
    'checked_in_workers',(select n from checked_in),
    'upcoming_jobs_7d',(select count(*) from upcoming),
    'unassigned_jobs_7d',(select count(*) from upcoming where filled < headcount),
    'live_headcount_gap',(select coalesce(sum(greatest(headcount-filled::integer,0)),0) from live),
    'sla_risk_jobs_72h',(select count(*) from upcoming where starts_at < p_as_of+interval '72 hours' and (100.0*filled/greatest(headcount,1)) < 85),
    'fulfilment_percent_7d',(select case when coalesce(sum(headcount),0)>0 then round(100.0*sum(filled)/sum(headcount),1) else 100 end from upcoming),
    'pending_labour_requisitions',(select count(*) from public.labour_requisitions where status='pending'),
    'submitted_timesheets',(select submitted_count from payroll),
    'approved_timesheets_unbatched_exposure',(select round(approved_exposure,2) from payroll),
    'locked_payroll_exposure',(select round(amount,2) from locked_payroll),
    'pending_billing_items',(select pending_count from billing),
    'invoice_ready_items',(select invoice_ready_count from billing),
    'billing_disputes',(select disputed_count from billing),
    'month_revenue',(select round(month_revenue,2) from billing),
    'month_gross_margin',(select round(month_margin,2) from billing),
    'month_gross_margin_pct',(select case when month_revenue>0 then round(100*month_margin/month_revenue,2) else 0 end from billing)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_management_cockpit(timestamptz) from public;
grant execute on function public.get_management_cockpit(timestamptz) to authenticated;

comment on function public.get_management_cockpit(timestamptz) is
'Privileged read-only management cockpit covering live/upcoming fulfilment, attendance presence, requisitions, payroll exposure, billing and margin. It performs no workflow mutations.';