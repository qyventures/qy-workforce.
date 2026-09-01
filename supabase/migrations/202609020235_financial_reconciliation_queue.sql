-- QY Workforce: read-safe payroll/client-billing reconciliation queue.
-- Detects financial drift without mutating payroll, payout or billing ledgers.

create table public.financial_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  timesheet_id uuid not null references public.timesheets(id) on delete restrict,
  payroll_batch_item_id uuid references public.payroll_batch_items(id) on delete restrict,
  worker_payout_id uuid references public.worker_payouts(id) on delete restrict,
  client_billing_item_id uuid references public.client_billing_items(id) on delete restrict,
  case_type text not null check (case_type in (
    'missing_payroll_item','missing_payout','missing_billing_item',
    'worker_amount_mismatch','client_amount_mismatch','payout_amount_mismatch'
  )),
  expected_amount numeric(12,2),
  observed_amount numeric(12,2),
  status text not null default 'open' check (status in ('open','investigating','resolved','dismissed')),
  resolution_note text,
  detected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  unique(timesheet_id,case_type)
);

alter table public.financial_reconciliation_cases enable row level security;
create policy financial_reconciliation_read on public.financial_reconciliation_cases
for select using (public.current_app_role() in ('finance','admin','auditor'));
revoke insert, update, delete on public.financial_reconciliation_cases from anon, authenticated;
grant select on public.financial_reconciliation_cases to authenticated;

create or replace function public.sync_financial_reconciliation_cases(p_start date,p_end date)
returns integer
language plpgsql security definer set search_path=public
as $$
declare v_count integer := 0; v_rows integer;
begin
  if public.current_app_role() not in ('finance','admin') then raise exception 'not authorised'; end if;
  if p_start is null or p_end is null or p_end < p_start or p_end > p_start + 366 then raise exception 'invalid reconciliation period'; end if;

  with eligible as (
    select t.id timesheet_id,t.worker_amount,t.client_amount
    from public.timesheets t
    join public.shift_assignments a on a.id=t.assignment_id
    join public.shifts s on s.id=a.shift_id
    where t.status in ('approved','payroll_ready') and s.starts_at::date between p_start and p_end
  )
  insert into public.financial_reconciliation_cases(timesheet_id,case_type,expected_amount,observed_amount)
  select e.timesheet_id,'missing_payroll_item',e.worker_amount,null
  from eligible e
  left join public.payroll_batch_items pbi on pbi.timesheet_id=e.timesheet_id
  where pbi.id is null
  on conflict(timesheet_id,case_type) do nothing;
  get diagnostics v_rows=row_count; v_count:=v_count+v_rows;

  with eligible as (
    select t.id timesheet_id,t.worker_amount,t.client_amount,pbi.id payroll_batch_item_id,pbi.gross_pay
    from public.timesheets t
    join public.shift_assignments a on a.id=t.assignment_id
    join public.shifts s on s.id=a.shift_id
    join public.payroll_batch_items pbi on pbi.timesheet_id=t.id
    where t.status in ('approved','payroll_ready') and s.starts_at::date between p_start and p_end
  )
  insert into public.financial_reconciliation_cases(timesheet_id,payroll_batch_item_id,case_type,expected_amount,observed_amount)
  select e.timesheet_id,e.payroll_batch_item_id,'worker_amount_mismatch',e.worker_amount,e.gross_pay
  from eligible e where round(coalesce(e.worker_amount,0),2) <> round(coalesce(e.gross_pay,0),2)
  on conflict(timesheet_id,case_type) do nothing;
  get diagnostics v_rows=row_count; v_count:=v_count+v_rows;

  with eligible as (
    select t.id timesheet_id,t.client_amount,b.id billing_id,b.client_amount observed
    from public.timesheets t
    join public.shift_assignments a on a.id=t.assignment_id
    join public.shifts s on s.id=a.shift_id
    left join public.client_billing_items b on b.timesheet_id=t.id
    where t.status in ('approved','payroll_ready') and s.starts_at::date between p_start and p_end
  )
  insert into public.financial_reconciliation_cases(timesheet_id,client_billing_item_id,case_type,expected_amount,observed_amount)
  select e.timesheet_id,e.billing_id,
    case when e.billing_id is null then 'missing_billing_item' else 'client_amount_mismatch' end,
    e.client_amount,e.observed
  from eligible e
  where e.billing_id is null or round(coalesce(e.client_amount,0),2) <> round(coalesce(e.observed,0),2)
  on conflict(timesheet_id,case_type) do nothing;
  get diagnostics v_rows=row_count; v_count:=v_count+v_rows;

  with eligible as (
    select t.id timesheet_id,pbi.id payroll_batch_item_id,wp.id payout_id,pbi.gross_pay,
           wp.payable_amount
    from public.timesheets t
    join public.shift_assignments a on a.id=t.assignment_id
    join public.shifts s on s.id=a.shift_id
    join public.payroll_batch_items pbi on pbi.timesheet_id=t.id
    left join public.worker_payouts wp on wp.payroll_batch_item_id=pbi.id
    where t.status in ('approved','payroll_ready') and s.starts_at::date between p_start and p_end
  )
  insert into public.financial_reconciliation_cases(timesheet_id,payroll_batch_item_id,worker_payout_id,case_type,expected_amount,observed_amount)
  select e.timesheet_id,e.payroll_batch_item_id,e.payout_id,
    case when e.payout_id is null then 'missing_payout' else 'payout_amount_mismatch' end,
    e.gross_pay,e.payable_amount
  from eligible e
  where e.payout_id is null or round(coalesce(e.gross_pay,0),2) <> round(coalesce(e.payable_amount,0),2)
  on conflict(timesheet_id,case_type) do nothing;
  get diagnostics v_rows=row_count; v_count:=v_count+v_rows;

  insert into public.audit_events(actor_id,action,entity_type,metadata)
  values(auth.uid(),'financial_reconciliation.synced','financial_reconciliation_case',jsonb_build_object('period_start',p_start,'period_end',p_end,'cases_created',v_count));
  return v_count;
end; $$;

create or replace function public.transition_financial_reconciliation_case(p_case uuid,p_status text,p_note text)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_old text;
begin
  if public.current_app_role() not in ('finance','admin') then raise exception 'not authorised'; end if;
  if p_status not in ('investigating','resolved','dismissed') then raise exception 'invalid reconciliation status'; end if;
  if char_length(trim(coalesce(p_note,''))) < 5 then raise exception 'resolution note required'; end if;
  select status into v_old from public.financial_reconciliation_cases where id=p_case for update;
  if v_old is null then raise exception 'reconciliation case not found'; end if;
  if not ((v_old='open' and p_status in ('investigating','resolved','dismissed')) or (v_old='investigating' and p_status in ('resolved','dismissed'))) then
    raise exception 'invalid reconciliation transition';
  end if;
  update public.financial_reconciliation_cases set status=p_status,resolution_note=left(trim(p_note),1000),updated_at=now(),
    resolved_by=case when p_status in ('resolved','dismissed') then auth.uid() else resolved_by end,
    resolved_at=case when p_status in ('resolved','dismissed') then now() else resolved_at end
  where id=p_case;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'financial_reconciliation.status_changed','financial_reconciliation_case',p_case,jsonb_build_object('from',v_old,'to',p_status));
end; $$;

revoke all on function public.sync_financial_reconciliation_cases(date,date) from public;
revoke all on function public.transition_financial_reconciliation_case(uuid,text,text) from public;
grant execute on function public.sync_financial_reconciliation_cases(date,date) to authenticated;
grant execute on function public.transition_financial_reconciliation_case(uuid,text,text) to authenticated;
