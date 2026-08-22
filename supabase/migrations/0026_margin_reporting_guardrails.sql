-- QY Workforce: bounded, audited client/site margin reporting.
-- Reporting remains aggregate-only; no worker identity fields are returned.

create or replace function public.get_site_margin_report(p_start date, p_end date)
returns table(
  site_id uuid,
  site_name text,
  client_id uuid,
  client_name text,
  shift_count bigint,
  approved_hours numeric,
  worker_cost numeric,
  client_revenue numeric,
  gross_margin numeric,
  gross_margin_pct numeric
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_app_role() not in ('ops_manager','finance','admin','auditor') then
    raise exception 'not authorised';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'invalid period';
  end if;
  if p_end - p_start > 366 then
    raise exception 'reporting period exceeds 366 days';
  end if;
  if p_end > current_date + 1 then
    raise exception 'future reporting period not allowed';
  end if;

  insert into public.audit_events(actor_id,action,entity_type,metadata)
  values(
    auth.uid(),
    'margin_report.viewed',
    'site_margin_report',
    jsonb_build_object('period_start',p_start,'period_end',p_end)
  );

  return query
  select si.id,si.name,c.id,c.name,
         count(distinct sh.id),
         round(coalesce(sum(t.payable_minutes),0)::numeric/60,2),
         round(coalesce(sum(t.worker_amount),0),2),
         round(coalesce(sum(t.client_amount),0),2),
         round(coalesce(sum(t.client_amount-t.worker_amount),0),2),
         case when coalesce(sum(t.client_amount),0)>0 then
           round(100*sum(t.client_amount-t.worker_amount)/sum(t.client_amount),2)
         else 0 end
  from public.timesheets t
  join public.shift_assignments sa on sa.id=t.assignment_id
  join public.shifts sh on sh.id=sa.shift_id
  join public.sites si on si.id=sh.site_id
  join public.clients c on c.id=si.client_id
  where t.status in ('approved','payroll_ready')
    and sh.starts_at::date between p_start and p_end
  group by si.id,si.name,c.id,c.name
  order by c.name,si.name;
end;
$$;

revoke all on function public.get_site_margin_report(date,date) from public;
grant execute on function public.get_site_margin_report(date,date) to authenticated;

comment on function public.get_site_margin_report(date,date) is
'Aggregate-only client/site margin report for privileged roles. Date range is bounded and each access is audited; worker identity is never returned.';
