-- QY Workforce V1: payroll integrity, immutability and export reconciliation
-- Keeps payroll mutations RPC-only, prevents duplicate active batching, and makes
-- lock/export transitions concurrency-safe and auditable.

alter table public.payroll_batches
  add column if not exists locked_by uuid references public.profiles(id),
  add column if not exists exported_by uuid references public.profiles(id);

-- Client roles may read through RLS but may not mutate payroll state directly.
revoke insert, update, delete on public.payroll_batches from authenticated;
revoke insert, update, delete on public.payroll_batch_items from authenticated;

-- Once a batch leaves draft, its membership is immutable even for privileged
-- database callers using ordinary SQL. This preserves the evidence represented
-- by the recorded export checksum/count.
create or replace function public.guard_payroll_batch_item_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_batch_id uuid := coalesce(new.payroll_batch_id, old.payroll_batch_id);
  v_status text;
begin
  select status into v_status
  from public.payroll_batches
  where id = v_batch_id;

  if v_status is null then
    raise exception 'payroll batch not found';
  end if;

  if v_status <> 'draft' then
    raise exception 'payroll batch membership is immutable after lock';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists payroll_batch_items_guard_mutation on public.payroll_batch_items;
create trigger payroll_batch_items_guard_mutation
before insert or update or delete on public.payroll_batch_items
for each row execute function public.guard_payroll_batch_item_mutation();

create or replace function public.create_payroll_batch(p_start date, p_end date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch uuid;
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'invalid pay period';
  end if;
  if p_end - p_start > 62 then
    raise exception 'pay period too large';
  end if;

  insert into public.payroll_batches(period_start, period_end, created_by)
  values (p_start, p_end, auth.uid())
  returning id into v_batch;

  -- A timesheet can belong to only one active payroll workflow. Draft batches
  -- count as active so two finance users cannot prepare conflicting batches.
  insert into public.payroll_batch_items(payroll_batch_id, timesheet_id, gross_pay)
  select v_batch, t.id, round(coalesce(t.worker_amount,0), 2)
  from public.timesheets t
  join public.shift_assignments sa on sa.id = t.assignment_id
  join public.shifts s on s.id = sa.shift_id
  where t.status = 'approved'
    and s.starts_at::date between p_start and p_end
    and not exists (
      select 1
      from public.payroll_batch_items pbi
      join public.payroll_batches pb on pb.id = pbi.payroll_batch_id
      where pbi.timesheet_id = t.id
        and pb.status <> 'cancelled'
    );

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_batch.created', 'payroll_batch', v_batch,
    jsonb_build_object(
      'period_start', p_start,
      'period_end', p_end,
      'item_count', (select count(*) from public.payroll_batch_items where payroll_batch_id=v_batch)
    )
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
  v_invalid_count integer;
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;

  select status into v_status
  from public.payroll_batches
  where id = p_batch
  for update;

  if v_status is null then raise exception 'batch not found'; end if;
  if v_status <> 'draft' then raise exception 'batch not draft'; end if;

  select count(*) into v_item_count
  from public.payroll_batch_items
  where payroll_batch_id = p_batch;
  if v_item_count = 0 then raise exception 'cannot lock empty payroll batch'; end if;

  -- Lock every member timesheet before validating state. This serializes
  -- payroll locking against supervisor/payroll transitions.
  perform 1
  from public.timesheets t
  join public.payroll_batch_items pbi on pbi.timesheet_id = t.id
  where pbi.payroll_batch_id = p_batch
  for update of t;

  select count(*) into v_invalid_count
  from public.timesheets t
  join public.payroll_batch_items pbi on pbi.timesheet_id = t.id
  where pbi.payroll_batch_id = p_batch
    and t.status <> 'approved';

  if v_invalid_count > 0 then
    raise exception 'batch contains timesheets no longer approved';
  end if;

  update public.timesheets t
  set status='payroll_ready',
      payroll_ready_at=coalesce(payroll_ready_at,now()),
      updated_at=now()
  where exists (
    select 1 from public.payroll_batch_items pbi
    where pbi.payroll_batch_id=p_batch and pbi.timesheet_id=t.id
  );

  update public.payroll_batches
  set status='locked', locked_at=now(), locked_by=auth.uid()
  where id=p_batch;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),'payroll_batch.locked','payroll_batch',p_batch,
    jsonb_build_object('item_count', v_item_count)
  );
end;
$$;

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
  v_batch public.payroll_batches%rowtype;
  v_actual_count integer;
  v_checksum text := lower(trim(coalesce(p_checksum,'')));
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;
  if p_format not in ('csv','json') then raise exception 'unsupported format'; end if;
  if v_checksum !~ '^[0-9a-f]{64}$' then raise exception 'sha256 checksum required'; end if;

  select * into v_batch
  from public.payroll_batches
  where id = p_batch
  for update;

  if not found then raise exception 'batch not found'; end if;
  if v_batch.status not in ('locked','exported') then
    raise exception 'payroll batch must be locked before export';
  end if;

  select count(*) into v_actual_count
  from public.payroll_batch_items
  where payroll_batch_id = p_batch;

  if p_count <> v_actual_count then
    raise exception 'export count does not match locked batch';
  end if;

  -- Re-recording an export is idempotent only if the evidence is identical.
  if v_batch.status = 'exported' then
    if v_batch.export_format is distinct from p_format
       or lower(coalesce(v_batch.export_checksum,'')) is distinct from v_checksum
       or v_batch.export_count is distinct from p_count then
      raise exception 'export evidence is immutable';
    end if;
    return;
  end if;

  update public.payroll_batches
  set status='exported',
      exported_at=now(),
      exported_by=auth.uid(),
      export_format=p_format,
      export_checksum=v_checksum,
      export_count=p_count
  where id=p_batch;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_export.recorded', 'payroll_batch', p_batch,
    jsonb_build_object('format', p_format, 'count', p_count, 'sha256', v_checksum)
  );
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
  v_reason text := left(trim(coalesce(p_reason,'')),500);
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;
  if v_reason = '' then raise exception 'cancellation reason required'; end if;

  select status into v_status
  from public.payroll_batches
  where id=p_batch
  for update;

  if v_status is null then raise exception 'batch not found'; end if;
  if v_status <> 'draft' then raise exception 'only draft payroll batches can be cancelled'; end if;

  update public.payroll_batches set status='cancelled' where id=p_batch;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(),'payroll_batch.cancelled','payroll_batch',p_batch,jsonb_build_object('reason',v_reason));
end;
$$;

revoke all on function public.create_payroll_batch(date,date) from public;
revoke all on function public.lock_payroll_batch(uuid) from public;
revoke all on function public.record_payroll_export(uuid,text,text,integer) from public;
revoke all on function public.cancel_payroll_batch(uuid,text) from public;
grant execute on function public.create_payroll_batch(date,date) to authenticated;
grant execute on function public.lock_payroll_batch(uuid) to authenticated;
grant execute on function public.record_payroll_export(uuid,text,text,integer) to authenticated;
grant execute on function public.cancel_payroll_batch(uuid,text) to authenticated;
