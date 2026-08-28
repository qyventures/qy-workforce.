-- QY Workforce: prevent one approved timesheet from being paid through multiple batches.
-- Draft cancellation is the only supported way to release a timesheet for re-batching.

do $$
begin
  if exists (
    select 1
    from public.payroll_batch_items
    group by timesheet_id
    having count(*) > 1
  ) then
    raise exception 'duplicate payroll batch memberships require reconciliation before this migration';
  end if;
end $$;

create unique index if not exists uq_payroll_batch_items_timesheet
  on public.payroll_batch_items(timesheet_id);

-- Payroll state transitions are audited RPC-only boundaries.
revoke insert, update, delete on public.payroll_batches from anon, authenticated;
revoke insert, update, delete on public.payroll_batch_items from anon, authenticated;

drop policy if exists payroll_batches_finance_write on public.payroll_batches;
drop policy if exists payroll_items_finance_write on public.payroll_batch_items;

create or replace function public.create_payroll_batch(p_start date, p_end date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch uuid;
  v_item_count integer;
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'invalid pay period';
  end if;

  insert into public.payroll_batches(period_start, period_end, created_by)
  values (p_start, p_end, auth.uid())
  returning id into v_batch;

  insert into public.payroll_batch_items(payroll_batch_id, timesheet_id, gross_pay)
  select v_batch, t.id, round(coalesce(t.worker_amount, 0), 2)
  from public.timesheets t
  join public.shift_assignments sa on sa.id = t.assignment_id
  join public.shifts s on s.id = sa.shift_id
  where t.status = 'approved'
    and s.starts_at::date between p_start and p_end
  on conflict (timesheet_id) do nothing;

  get diagnostics v_item_count = row_count;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_batch.created', 'payroll_batch', v_batch,
    jsonb_build_object('period_start', p_start, 'period_end', p_end, 'item_count', v_item_count)
  );
  return v_batch;
end;
$$;

create or replace function public.lock_payroll_batch(p_batch uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_item_count integer;
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;

  select status into v_status
  from public.payroll_batches
  where id = p_batch
  for update;

  if v_status is distinct from 'draft' then
    raise exception 'batch not found or not draft';
  end if;

  select count(*) into v_item_count
  from public.payroll_batch_items
  where payroll_batch_id = p_batch;

  if v_item_count = 0 then
    raise exception 'empty payroll batch cannot be locked';
  end if;
  if exists (
    select 1
    from public.payroll_batch_items pbi
    join public.timesheets t on t.id = pbi.timesheet_id
    where pbi.payroll_batch_id = p_batch
      and t.status <> 'approved'
  ) then
    raise exception 'batch contains a timesheet that is no longer approved';
  end if;

  update public.payroll_batches
  set status = 'locked', locked_at = now()
  where id = p_batch;

  update public.timesheets t
  set status = 'payroll_ready', payroll_ready_at = coalesce(payroll_ready_at, now()), updated_at = now()
  where exists (
    select 1
    from public.payroll_batch_items pbi
    where pbi.payroll_batch_id = p_batch and pbi.timesheet_id = t.id
  );

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'payroll_batch.locked', 'payroll_batch', p_batch,
          jsonb_build_object('item_count', v_item_count));
end;
$$;

create or replace function public.cancel_payroll_batch(p_batch uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_item_count integer;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;
  if length(v_reason) < 10 or length(v_reason) > 500 then
    raise exception 'cancellation reason must be between 10 and 500 characters';
  end if;

  select status into v_status
  from public.payroll_batches
  where id = p_batch
  for update;

  if v_status is distinct from 'draft' then
    raise exception 'only a draft payroll batch can be cancelled';
  end if;

  delete from public.payroll_batch_items
  where payroll_batch_id = p_batch;
  get diagnostics v_item_count = row_count;

  update public.payroll_batches
  set status = 'cancelled'
  where id = p_batch;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_batch.cancelled', 'payroll_batch', p_batch,
    jsonb_build_object('reason', v_reason, 'released_item_count', v_item_count)
  );
end;
$$;

revoke all on function public.create_payroll_batch(date,date) from public, anon;
revoke all on function public.lock_payroll_batch(uuid) from public, anon;
revoke all on function public.cancel_payroll_batch(uuid,text) from public, anon;
grant execute on function public.create_payroll_batch(date,date) to authenticated;
grant execute on function public.lock_payroll_batch(uuid) to authenticated;
grant execute on function public.cancel_payroll_batch(uuid,text) to authenticated;

comment on index public.uq_payroll_batch_items_timesheet is
  'A timesheet may belong to only one payroll batch; cancelling a draft releases it by deleting the draft membership.';
comment on function public.cancel_payroll_batch(uuid,text) is
  'Cancels only draft payroll batches, releases their timesheets for re-batching, and records a minimised operational reason.';
