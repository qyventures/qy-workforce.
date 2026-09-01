-- QY Workforce: make worker payouts operational with dual control and immutable preparation inputs.

alter table public.worker_payouts
  add column if not exists prepared_by uuid references public.profiles(id);

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
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_kind not in ('incentive','deduction','correction','reimbursement','other') then raise exception 'invalid adjustment kind'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'adjustment amount cannot be zero'; end if;
  if char_length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'reason must be 3 to 500 characters'; end if;
  if not exists (
    select 1 from public.payroll_batch_items pbi
    join public.payroll_batches pb on pb.id=pbi.payroll_batch_id
    where pbi.id=p_batch_item and pb.status in ('locked','exported')
  ) then raise exception 'payroll batch must be locked'; end if;
  if exists(select 1 from public.worker_payouts wp where wp.payroll_batch_item_id=p_batch_item) then
    raise exception 'payout already prepared; adjustment inputs are frozen';
  end if;

  insert into public.payroll_adjustments(payroll_batch_item_id,kind,amount,reason,created_by)
  values(p_batch_item,p_kind,round(p_amount,2),trim(p_reason),auth.uid()) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'payroll_adjustment.created','payroll_adjustment',v_id,
    jsonb_build_object('batch_item',p_batch_item,'kind',p_kind,'amount',round(p_amount,2)));
  return v_id;
end; $$;

create or replace function public.review_payroll_adjustment(p_adjustment uuid,p_approve boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare v_created_by uuid; v_batch_item uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;

  select created_by,payroll_batch_item_id into v_created_by,v_batch_item
  from public.payroll_adjustments where id=p_adjustment and status='pending' for update;
  if not found then raise exception 'adjustment not found or already reviewed'; end if;
  if v_created_by=auth.uid() then raise exception 'self review is not permitted'; end if;
  if exists(select 1 from public.worker_payouts where payroll_batch_item_id=v_batch_item) then
    raise exception 'payout already prepared; adjustment inputs are frozen';
  end if;

  update public.payroll_adjustments
  set status=case when p_approve then 'approved' else 'rejected' end,
      reviewed_by=auth.uid(), reviewed_at=now()
  where id=p_adjustment and status='pending';

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),case when p_approve then 'payroll_adjustment.approved' else 'payroll_adjustment.rejected' end,
    'payroll_adjustment',p_adjustment,'{}'::jsonb);
end; $$;

create or replace function public.prepare_worker_payouts(p_batch uuid)
returns integer language plpgsql security definer set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.payroll_batches where id=p_batch and status in ('locked','exported')) then
    raise exception 'payroll batch must be locked';
  end if;
  if exists (
    select 1 from public.payroll_adjustments pa
    join public.payroll_batch_items pbi on pbi.id=pa.payroll_batch_item_id
    where pbi.payroll_batch_id=p_batch and pa.status='pending'
  ) then raise exception 'pending adjustments must be reviewed before payout preparation'; end if;

  insert into public.worker_payouts(payroll_batch_item_id,base_amount,adjustment_amount,prepared_by)
  select pbi.id,pbi.gross_pay,
         coalesce(sum(pa.amount) filter (where pa.status='approved'),0),auth.uid()
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
declare v_old text; v_method text; v_prepared_by uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_status not in ('approved','processing','paid','failed','cancelled') then raise exception 'invalid payout status'; end if;

  select status,method,prepared_by into v_old,v_method,v_prepared_by
  from public.worker_payouts where id=p_payout for update;
  if not found then raise exception 'payout not found'; end if;
  if p_status='approved' and v_prepared_by=auth.uid() then raise exception 'payout preparer cannot approve the same payout'; end if;
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
  if v_method='cash_exception' and char_length(trim(coalesce(p_exception_reason,''))) not between 5 and 500 then
    raise exception 'cash exception requires a 5 to 500 character reason';
  end if;
  if p_external_reference is not null and char_length(trim(p_external_reference)) > 200 then
    raise exception 'external reference too long';
  end if;

  update public.worker_payouts set
    status=p_status, method=v_method,
    exception_reason=case when v_method='cash_exception' then trim(p_exception_reason) else null end,
    external_reference=coalesce(nullif(trim(p_external_reference),''),external_reference),
    approved_by=case when p_status='approved' then auth.uid() else approved_by end,
    approved_at=case when p_status='approved' then now() else approved_at end,
    paid_at=case when p_status='paid' then now() else paid_at end,
    updated_at=now()
  where id=p_payout;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_payout.status_changed','worker_payout',p_payout,
    jsonb_build_object('from',v_old,'to',p_status,'method',v_method));
end; $$;

create or replace function public.get_worker_payout_control_queue(p_batch uuid)
returns table (
  payout_id uuid, batch_item_id uuid, worker_label text, shift_date date, site_name text,
  base_amount numeric, adjustment_amount numeric, payable_amount numeric, currency text,
  method text, status text, external_reference text, prepared_by_me boolean
)
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('admin','finance','auditor') then raise exception 'not authorised'; end if;
  return query
  select wp.id,pbi.id,'Worker #' || upper(substr(md5(sa.worker_id::text),1,8)),sh.starts_at::date,s.name,
    wp.base_amount,wp.adjustment_amount,wp.payable_amount,wp.currency,wp.method,wp.status,
    wp.external_reference,(wp.prepared_by=auth.uid())
  from public.worker_payouts wp
  join public.payroll_batch_items pbi on pbi.id=wp.payroll_batch_item_id
  join public.timesheets t on t.id=pbi.timesheet_id
  join public.shift_assignments sa on sa.id=t.assignment_id
  join public.shifts sh on sh.id=sa.shift_id
  join public.sites s on s.id=sh.site_id
  where pbi.payroll_batch_id=p_batch
  order by sh.starts_at,wp.id;
end; $$;

revoke all on function public.get_worker_payout_control_queue(uuid) from public;
grant execute on function public.get_worker_payout_control_queue(uuid) to authenticated;
