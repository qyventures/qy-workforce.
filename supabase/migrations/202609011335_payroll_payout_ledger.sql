-- QY Workforce: controlled payout ledger, adjustments and cash-paid exceptions

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  payroll_batch_item_id uuid not null references public.payroll_batch_items(id),
  kind text not null check (kind in ('incentive','deduction','correction','reimbursement','other')),
  amount numeric(12,2) not null check (amount <> 0),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.worker_payouts (
  id uuid primary key default gen_random_uuid(),
  payroll_batch_item_id uuid not null unique references public.payroll_batch_items(id),
  base_amount numeric(12,2) not null check (base_amount >= 0),
  adjustment_amount numeric(12,2) not null default 0,
  payable_amount numeric(12,2) generated always as (base_amount + adjustment_amount) stored,
  currency text not null default 'SGD',
  method text not null default 'bank' check (method in ('bank','cash_exception','other')),
  status text not null default 'pending' check (status in ('pending','approved','processing','paid','failed','cancelled')),
  external_reference text,
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  paid_at timestamptz,
  exception_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (payable_amount >= 0),
  check (method <> 'cash_exception' or char_length(trim(coalesce(exception_reason,''))) >= 5)
);

alter table public.payroll_adjustments enable row level security;
alter table public.worker_payouts enable row level security;

create policy payroll_adjustments_read on public.payroll_adjustments
for select using (public.current_app_role() in ('admin','finance','auditor'));

create policy worker_payouts_read on public.worker_payouts
for select using (public.current_app_role() in ('admin','finance','auditor'));

revoke insert, update, delete on public.payroll_adjustments from authenticated;
revoke insert, update, delete on public.worker_payouts from authenticated;

grant select on public.payroll_adjustments to authenticated;
grant select on public.worker_payouts to authenticated;

create or replace function public.add_payroll_adjustment(
  p_batch_item uuid,
  p_kind text,
  p_amount numeric,
  p_reason text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_kind not in ('incentive','deduction','correction','reimbursement','other') then raise exception 'invalid adjustment kind'; end if;
  if p_amount = 0 then raise exception 'adjustment amount cannot be zero'; end if;
  if char_length(trim(coalesce(p_reason,''))) < 3 then raise exception 'reason required'; end if;

  insert into public.payroll_adjustments(payroll_batch_item_id,kind,amount,reason,created_by)
  values(p_batch_item,p_kind,round(p_amount,2),trim(p_reason),auth.uid()) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'payroll_adjustment.created','payroll_adjustment',v_id,jsonb_build_object('batch_item',p_batch_item,'kind',p_kind,'amount',round(p_amount,2)));
  return v_id;
end; $$;

create or replace function public.review_payroll_adjustment(p_adjustment uuid,p_approve boolean)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  update public.payroll_adjustments
  set status=case when p_approve then 'approved' else 'rejected' end,
      reviewed_by=auth.uid(), reviewed_at=now()
  where id=p_adjustment and status='pending';
  if not found then raise exception 'adjustment not found or already reviewed'; end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),case when p_approve then 'payroll_adjustment.approved' else 'payroll_adjustment.rejected' end,'payroll_adjustment',p_adjustment,'{}'::jsonb);
end; $$;

create or replace function public.prepare_worker_payouts(p_batch uuid)
returns integer language plpgsql security definer set search_path = public
as $$
declare v_count integer;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.payroll_batches where id=p_batch and status in ('locked','exported')) then
    raise exception 'payroll batch must be locked';
  end if;

  insert into public.worker_payouts(payroll_batch_item_id,base_amount,adjustment_amount)
  select pbi.id,pbi.gross_pay,
         coalesce(sum(pa.amount) filter (where pa.status='approved'),0)
  from public.payroll_batch_items pbi
  left join public.payroll_adjustments pa on pa.payroll_batch_item_id=pbi.id
  where pbi.payroll_batch_id=p_batch
  group by pbi.id,pbi.gross_pay
  on conflict (payroll_batch_item_id) do nothing;
  get diagnostics v_count = row_count;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_payouts.prepared','payroll_batch',p_batch,jsonb_build_object('count',v_count));
  return v_count;
end; $$;

create or replace function public.set_worker_payout_status(
  p_payout uuid,
  p_status text,
  p_external_reference text default null,
  p_method text default null,
  p_exception_reason text default null
) returns void language plpgsql security definer set search_path = public
as $$
declare v_old text; v_method text;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_status not in ('approved','processing','paid','failed','cancelled') then raise exception 'invalid payout status'; end if;

  select status,method into v_old,v_method from public.worker_payouts where id=p_payout for update;
  if v_old is null then raise exception 'payout not found'; end if;
  if not ((v_old='pending' and p_status in ('approved','cancelled')) or
          (v_old='approved' and p_status in ('processing','paid','cancelled')) or
          (v_old='processing' and p_status in ('paid','failed')) or
          (v_old='failed' and p_status in ('processing','cancelled'))) then
    raise exception 'invalid payout transition';
  end if;

  if p_method is not null then
    if p_method not in ('bank','cash_exception','other') then raise exception 'invalid payout method'; end if;
    v_method := p_method;
  end if;
  if v_method='cash_exception' and char_length(trim(coalesce(p_exception_reason,''))) < 5 then
    raise exception 'cash exception requires reason';
  end if;

  update public.worker_payouts set
    status=p_status,
    method=v_method,
    exception_reason=case when v_method='cash_exception' then trim(p_exception_reason) else exception_reason end,
    external_reference=coalesce(p_external_reference,external_reference),
    approved_by=case when p_status='approved' then auth.uid() else approved_by end,
    approved_at=case when p_status='approved' then now() else approved_at end,
    paid_at=case when p_status='paid' then now() else paid_at end,
    updated_at=now()
  where id=p_payout;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_payout.status_changed','worker_payout',p_payout,jsonb_build_object('from',v_old,'to',p_status,'method',v_method));
end; $$;

revoke all on function public.add_payroll_adjustment(uuid,text,numeric,text) from public;
revoke all on function public.review_payroll_adjustment(uuid,boolean) from public;
revoke all on function public.prepare_worker_payouts(uuid) from public;
revoke all on function public.set_worker_payout_status(uuid,text,text,text,text) from public;
grant execute on function public.add_payroll_adjustment(uuid,text,numeric,text) to authenticated;
grant execute on function public.review_payroll_adjustment(uuid,boolean) to authenticated;
grant execute on function public.prepare_worker_payouts(uuid) to authenticated;
grant execute on function public.set_worker_payout_status(uuid,text,text,text,text) to authenticated;
