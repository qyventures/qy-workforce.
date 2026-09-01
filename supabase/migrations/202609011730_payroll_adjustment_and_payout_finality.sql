-- Preserve payroll-export finality and require independent review of adjustments.
-- This migration does not store payment-rail or bank-account details.

revoke all on table public.payroll_adjustments from public, anon, authenticated;
revoke all on table public.worker_payouts from public, anon, authenticated;
grant select on table public.payroll_adjustments to authenticated;
grant select on table public.worker_payouts to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payroll_adjustments'::regclass
      and conname = 'payroll_adjustments_review_state_check'
  ) then
    alter table public.payroll_adjustments add constraint payroll_adjustments_review_state_check
      check (
        (status = 'pending' and reviewed_by is null and reviewed_at is null)
        or (status in ('approved', 'rejected') and reviewed_by is not null and reviewed_at is not null)
      ) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payroll_adjustments'::regclass
      and conname = 'payroll_adjustments_independent_review_check'
  ) then
    alter table public.payroll_adjustments add constraint payroll_adjustments_independent_review_check
      check (reviewed_by is null or reviewed_by <> created_by) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.worker_payouts'::regclass
      and conname = 'worker_payouts_external_reference_check'
  ) then
    alter table public.worker_payouts add constraint worker_payouts_external_reference_check
      check (external_reference is null or char_length(trim(external_reference)) between 3 and 256) not valid;
  end if;
end;
$$;

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
  if p_amount is null or p_amount = 0 then raise exception 'adjustment amount cannot be zero'; end if;
  if char_length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'valid adjustment reason required'; end if;

  perform 1
  from public.payroll_batch_items pbi
  join public.payroll_batches pb on pb.id = pbi.payroll_batch_id
  where pbi.id = p_batch_item and pb.status = 'locked'
  for update of pb;
  if not found then raise exception 'adjustments require a locked, unexported payroll batch'; end if;

  insert into public.payroll_adjustments(payroll_batch_item_id,kind,amount,reason,created_by)
  values(p_batch_item,p_kind,round(p_amount,2),trim(p_reason),auth.uid()) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'payroll_adjustment.created','payroll_adjustment',v_id,jsonb_build_object('batch_item',p_batch_item,'kind',p_kind,'amount',round(p_amount,2)));
  return v_id;
end; $$;

create or replace function public.review_payroll_adjustment(p_adjustment uuid,p_approve boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_item uuid;
  v_creator uuid;
  v_status text;
  v_batch_status text;
  v_payout_status text;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_approve is null then raise exception 'review decision required'; end if;

  select pa.payroll_batch_item_id, pa.created_by, pa.status, pb.status
    into v_item, v_creator, v_status, v_batch_status
  from public.payroll_adjustments pa
  join public.payroll_batch_items pbi on pbi.id = pa.payroll_batch_item_id
  join public.payroll_batches pb on pb.id = pbi.payroll_batch_id
  where pa.id = p_adjustment
  for update of pa, pb;
  if v_item is null or v_status <> 'pending' then raise exception 'adjustment not found or already reviewed'; end if;
  if v_creator = auth.uid() then raise exception 'self review is not permitted'; end if;
  if v_batch_status <> 'locked' then raise exception 'adjustments cannot be reviewed after export'; end if;

  select status into v_payout_status from public.worker_payouts
  where payroll_batch_item_id = v_item for update;
  if v_payout_status is not null and v_payout_status <> 'pending' then
    raise exception 'adjustment cannot change a non-pending payout';
  end if;

  update public.payroll_adjustments
  set status=case when p_approve then 'approved' else 'rejected' end,
      reviewed_by=auth.uid(), reviewed_at=clock_timestamp()
  where id=p_adjustment;

  if v_payout_status = 'pending' then
    update public.worker_payouts wp
    set adjustment_amount = coalesce((
          select sum(pa.amount) from public.payroll_adjustments pa
          where pa.payroll_batch_item_id = v_item and pa.status = 'approved'
        ), 0),
        updated_at = clock_timestamp()
    where wp.payroll_batch_item_id = v_item;
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),case when p_approve then 'payroll_adjustment.approved' else 'payroll_adjustment.rejected' end,'payroll_adjustment',p_adjustment,jsonb_build_object('independent_review',true));
end; $$;

create or replace function public.prepare_worker_payouts(p_batch uuid)
returns integer language plpgsql security definer set search_path = public
as $$
declare v_count integer;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  perform 1 from public.payroll_batches where id=p_batch and status='locked' for update;
  if not found then raise exception 'payout preparation requires a locked, unexported payroll batch'; end if;

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

create or replace function public.record_payroll_export(
  p_batch uuid,
  p_format text,
  p_checksum text,
  p_count integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_export_format text;
  v_export_checksum text;
  v_export_count integer;
  v_actual_count integer;
  v_format text := lower(trim(coalesce(p_format, '')));
  v_checksum text := lower(trim(coalesce(p_checksum, '')));
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if v_format not in ('csv','json') then raise exception 'unsupported format'; end if;
  if v_checksum !~ '^[0-9a-f]{64}$' then raise exception 'SHA-256 checksum required'; end if;
  if p_count is null or p_count < 0 then raise exception 'invalid export count'; end if;

  select status, export_format, export_checksum, export_count
    into v_status, v_export_format, v_export_checksum, v_export_count
  from public.payroll_batches where id = p_batch for update;
  if v_status is null then raise exception 'payroll batch not found'; end if;

  select count(*)::integer into v_actual_count
  from public.payroll_batch_items where payroll_batch_id = p_batch;
  if p_count <> v_actual_count then raise exception 'export count does not match payroll batch'; end if;

  if v_status = 'exported' then
    if v_export_format = v_format and v_export_checksum = v_checksum and v_export_count = p_count then return; end if;
    raise exception 'payroll export evidence is immutable';
  end if;
  if v_status <> 'locked' then raise exception 'payroll batch must be locked before export'; end if;
  if exists (
    select 1 from public.payroll_batch_items pbi
    where pbi.payroll_batch_id = p_batch
      and not exists (select 1 from public.worker_payouts wp where wp.payroll_batch_item_id = pbi.id)
  ) then raise exception 'all payroll payouts must be prepared before export'; end if;
  if exists (
    select 1 from public.payroll_adjustments pa
    join public.payroll_batch_items pbi on pbi.id = pa.payroll_batch_item_id
    where pbi.payroll_batch_id = p_batch and pa.status = 'pending'
  ) then raise exception 'pending payroll adjustments must be resolved before export'; end if;

  update public.payroll_batches
  set status = 'exported', exported_at = clock_timestamp(), export_format = v_format,
      export_checksum = v_checksum, export_count = p_count
  where id = p_batch and status = 'locked';
  if not found then raise exception 'payroll export conflict'; end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'payroll_export.recorded', 'payroll_batch', p_batch,
    jsonb_build_object('format', v_format, 'count', p_count, 'checksum', v_checksum,
      'payouts_prepared', true, 'pending_adjustments', false));
end;
$$;

create or replace function public.set_worker_payout_status(
  p_payout uuid,
  p_status text,
  p_external_reference text default null,
  p_method text default null,
  p_exception_reason text default null
) returns void language plpgsql security definer set search_path = public
as $$
declare
  v_old text;
  v_method text;
  v_reference text;
  v_exception_reason text;
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_status not in ('approved','processing','paid','failed','cancelled') then raise exception 'invalid payout status'; end if;

  select status,method,external_reference,exception_reason
    into v_old,v_method,v_reference,v_exception_reason
  from public.worker_payouts where id=p_payout for update;
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
  v_reference := nullif(trim(coalesce(p_external_reference,v_reference)), '');
  v_exception_reason := nullif(trim(coalesce(p_exception_reason,v_exception_reason)), '');
  if v_reference is not null and char_length(v_reference) not between 3 and 256 then raise exception 'valid external reference required'; end if;
  if v_method='cash_exception' and char_length(coalesce(v_exception_reason,'')) < 5 then raise exception 'cash exception requires reason'; end if;
  if p_status='paid' and v_reference is null then raise exception 'paid payout requires external reference'; end if;

  update public.worker_payouts set
    status=p_status, method=v_method, exception_reason=case when v_method='cash_exception' then v_exception_reason else exception_reason end,
    external_reference=v_reference,
    approved_by=case when p_status='approved' then auth.uid() else approved_by end,
    approved_at=case when p_status='approved' then clock_timestamp() else approved_at end,
    paid_at=case when p_status='paid' then clock_timestamp() else paid_at end,
    updated_at=clock_timestamp()
  where id=p_payout;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_payout.status_changed','worker_payout',p_payout,jsonb_build_object('from',v_old,'to',p_status,'method',v_method,'external_reference_present',v_reference is not null));
end; $$;

revoke all on function public.add_payroll_adjustment(uuid,text,numeric,text) from public, anon;
revoke all on function public.review_payroll_adjustment(uuid,boolean) from public, anon;
revoke all on function public.prepare_worker_payouts(uuid) from public, anon;
revoke all on function public.set_worker_payout_status(uuid,text,text,text,text) from public, anon;
grant execute on function public.add_payroll_adjustment(uuid,text,numeric,text) to authenticated;
grant execute on function public.review_payroll_adjustment(uuid,boolean) to authenticated;
grant execute on function public.prepare_worker_payouts(uuid) to authenticated;
grant execute on function public.set_worker_payout_status(uuid,text,text,text,text) to authenticated;

comment on function public.review_payroll_adjustment(uuid,boolean) is
  'Finance/Admin-only, independent adjustment review. Locks the adjustment and batch, and cannot change exported or non-pending payout amounts.';
comment on function public.prepare_worker_payouts(uuid) is
  'Creates payout rows only while a payroll batch remains locked and unexported.';
comment on function public.record_payroll_export(uuid,text,text,integer) is
  'Finance/Admin-only immutable export finalization; requires prepared payouts and no pending adjustments.';
