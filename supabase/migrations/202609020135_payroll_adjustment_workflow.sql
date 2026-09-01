-- QY Workforce: audited payroll adjustment / incentive / cash-paid exception workflow

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  timesheet_id uuid not null references public.timesheets(id),
  payroll_batch_id uuid references public.payroll_batches(id),
  adjustment_type text not null check (adjustment_type in ('correction','incentive','deduction','cash_paid_exception','other')),
  amount numeric(12,2) not null check (amount <> 0),
  currency text not null default 'SGD' check (char_length(currency)=3),
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected','applied')),
  requested_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  applied_by uuid references public.profiles(id),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (reviewed_by is null or reviewed_by <> requested_by),
  check ((status in ('approved','rejected','applied')) = (reviewed_by is not null)),
  check ((status='applied') = (applied_at is not null))
);

create index if not exists payroll_adjustments_timesheet_idx on public.payroll_adjustments(timesheet_id, created_at desc);
create index if not exists payroll_adjustments_status_idx on public.payroll_adjustments(status, created_at);

alter table public.payroll_adjustments enable row level security;

-- Finance/admin may read all. Ops managers may read for operational reconciliation.
create policy payroll_adjustments_read on public.payroll_adjustments
for select using (public.current_app_role() in ('admin','finance','ops_manager','auditor'));

-- Deny direct authenticated writes; all state transitions go through audited RPCs.
revoke insert, update, delete on public.payroll_adjustments from authenticated;

grant select on public.payroll_adjustments to authenticated;

create or replace function public.create_payroll_adjustment(
  p_timesheet uuid,
  p_type text,
  p_amount numeric,
  p_reason text,
  p_batch uuid default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if public.current_app_role() not in ('admin','finance','ops_manager') then raise exception 'not authorised'; end if;
  if p_type not in ('correction','incentive','deduction','cash_paid_exception','other') then raise exception 'invalid adjustment type'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'amount must be non-zero'; end if;
  if nullif(trim(p_reason),'') is null or char_length(trim(p_reason)) < 3 then raise exception 'reason required'; end if;
  if not exists (select 1 from public.timesheets where id=p_timesheet) then raise exception 'timesheet not found'; end if;
  if p_batch is not null and not exists (select 1 from public.payroll_batches where id=p_batch and status in ('draft','locked')) then
    raise exception 'batch not found or already exported/cancelled';
  end if;

  insert into public.payroll_adjustments(timesheet_id,payroll_batch_id,adjustment_type,amount,reason,requested_by)
  values (p_timesheet,p_batch,p_type,round(p_amount,2),left(trim(p_reason),1000),auth.uid()) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'payroll_adjustment.created','payroll_adjustment',v_id,jsonb_build_object('timesheet_id',p_timesheet,'type',p_type,'amount',round(p_amount,2),'batch_id',p_batch));
  return v_id;
end; $$;

create or replace function public.submit_payroll_adjustment(p_adjustment uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_app_role() not in ('admin','finance','ops_manager') then raise exception 'not authorised'; end if;
  update public.payroll_adjustments set status='submitted',updated_at=now()
  where id=p_adjustment and status='draft' and requested_by=auth.uid();
  if not found then raise exception 'adjustment not found, not draft, or not requester'; end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id) values(auth.uid(),'payroll_adjustment.submitted','payroll_adjustment',p_adjustment);
end; $$;

create or replace function public.review_payroll_adjustment(p_adjustment uuid,p_approve boolean,p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_requested uuid;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  select requested_by into v_requested from public.payroll_adjustments where id=p_adjustment and status='submitted' for update;
  if v_requested is null then raise exception 'adjustment not found or not submitted'; end if;
  if v_requested=auth.uid() then raise exception 'requester cannot review own adjustment'; end if;
  update public.payroll_adjustments
  set status=case when p_approve then 'approved' else 'rejected' end, reviewed_by=auth.uid(), reviewed_at=now(), updated_at=now()
  where id=p_adjustment;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),case when p_approve then 'payroll_adjustment.approved' else 'payroll_adjustment.rejected' end,'payroll_adjustment',p_adjustment,jsonb_build_object('review_note',left(coalesce(trim(p_note),''),1000)));
end; $$;

create or replace function public.apply_payroll_adjustment(p_adjustment uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_batch uuid; v_timesheet uuid; v_amount numeric;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  select payroll_batch_id,timesheet_id,amount into v_batch,v_timesheet,v_amount
  from public.payroll_adjustments where id=p_adjustment and status='approved' for update;
  if v_timesheet is null then raise exception 'adjustment not found or not approved'; end if;

  if v_batch is not null then
    if not exists(select 1 from public.payroll_batches where id=v_batch and status='draft') then raise exception 'only draft payroll batches may be adjusted'; end if;
    update public.payroll_batch_items set gross_pay=round(gross_pay+v_amount,2)
    where payroll_batch_id=v_batch and timesheet_id=v_timesheet;
    if not found then raise exception 'timesheet is not in the selected payroll batch'; end if;
  end if;

  update public.payroll_adjustments set status='applied',applied_by=auth.uid(),applied_at=now(),updated_at=now() where id=p_adjustment;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'payroll_adjustment.applied','payroll_adjustment',p_adjustment,jsonb_build_object('batch_id',v_batch,'amount',v_amount));
end; $$;

revoke all on function public.create_payroll_adjustment(uuid,text,numeric,text,uuid) from public;
revoke all on function public.submit_payroll_adjustment(uuid) from public;
revoke all on function public.review_payroll_adjustment(uuid,boolean,text) from public;
revoke all on function public.apply_payroll_adjustment(uuid) from public;
grant execute on function public.create_payroll_adjustment(uuid,text,numeric,text,uuid) to authenticated;
grant execute on function public.submit_payroll_adjustment(uuid) to authenticated;
grant execute on function public.review_payroll_adjustment(uuid,boolean,text) to authenticated;
grant execute on function public.apply_payroll_adjustment(uuid) to authenticated;
