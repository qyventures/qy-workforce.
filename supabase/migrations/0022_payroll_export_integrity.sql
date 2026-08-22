-- QY Workforce: make payroll locking and export evidence server-authoritative.
-- Finance/Admin retain read access through RLS, but all mutations flow through
-- audited RPCs. A transaction advisory lock prevents two draft batches from
-- locking the same timesheet concurrently.

drop policy if exists payroll_batches_finance_write on public.payroll_batches;
drop policy if exists payroll_items_finance_write on public.payroll_batch_items;

revoke insert, update, delete on public.payroll_batches from authenticated;
revoke insert, update, delete on public.payroll_batch_items from authenticated;

-- The legacy finalizer did not bind an export to its format, checksum or count.
revoke all on function public.mark_payroll_batch_exported(uuid) from authenticated;

create or replace function public.lock_payroll_batch(p_batch uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('qy:payroll:batch-lock', 0));

  select status into v_status
  from public.payroll_batches
  where id = p_batch
  for update;

  if v_status is null then raise exception 'payroll batch not found'; end if;
  if v_status <> 'draft' then raise exception 'payroll batch is not draft'; end if;
  if not exists (
    select 1 from public.payroll_batch_items where payroll_batch_id = p_batch
  ) then raise exception 'empty payroll batch cannot be locked'; end if;

  if exists (
    select 1
    from public.payroll_batch_items candidate
    join public.payroll_batch_items prior on prior.timesheet_id = candidate.timesheet_id
    join public.payroll_batches prior_batch on prior_batch.id = prior.payroll_batch_id
    where candidate.payroll_batch_id = p_batch
      and prior.payroll_batch_id <> p_batch
      and prior_batch.status in ('locked','exported')
  ) then raise exception 'timesheet already belongs to a locked payroll batch'; end if;

  if exists (
    select 1
    from public.payroll_batch_items pbi
    join public.timesheets t on t.id = pbi.timesheet_id
    where pbi.payroll_batch_id = p_batch
      and t.status <> 'approved'
  ) then raise exception 'payroll batch contains a timesheet that is not approved'; end if;

  update public.payroll_batches
  set status = 'locked', locked_at = now()
  where id = p_batch;

  update public.timesheets t
  set status = 'payroll_ready',
      payroll_ready_at = coalesce(payroll_ready_at, now()),
      updated_at = now()
  where t.status = 'approved'
    and exists (
      select 1 from public.payroll_batch_items pbi
      where pbi.payroll_batch_id = p_batch and pbi.timesheet_id = t.id
    );

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_batch.locked', 'payroll_batch', p_batch,
    jsonb_build_object(
      'item_count', (select count(*) from public.payroll_batch_items where payroll_batch_id = p_batch),
      'duplicate_guard', true
    )
  );
end;
$$;

revoke all on function public.lock_payroll_batch(uuid) from public;
grant execute on function public.lock_payroll_batch(uuid) to authenticated;

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
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;
  if v_format not in ('csv','json') then raise exception 'unsupported format'; end if;
  if v_checksum !~ '^[0-9a-f]{64}$' then raise exception 'SHA-256 checksum required'; end if;
  if p_count is null or p_count < 0 then raise exception 'invalid export count'; end if;

  select status, export_format, export_checksum, export_count
    into v_status, v_export_format, v_export_checksum, v_export_count
  from public.payroll_batches
  where id = p_batch
  for update;

  if v_status is null then raise exception 'payroll batch not found'; end if;

  select count(*)::integer into v_actual_count
  from public.payroll_batch_items
  where payroll_batch_id = p_batch;

  if p_count <> v_actual_count then raise exception 'export count does not match payroll batch'; end if;

  if v_status = 'exported' then
    if v_export_format = v_format
       and v_export_checksum = v_checksum
       and v_export_count = p_count then
      return;
    end if;
    raise exception 'payroll export evidence is immutable';
  end if;
  if v_status <> 'locked' then raise exception 'payroll batch must be locked before export'; end if;

  update public.payroll_batches
  set status = 'exported',
      exported_at = now(),
      export_format = v_format,
      export_checksum = v_checksum,
      export_count = p_count
  where id = p_batch and status = 'locked';

  if not found then raise exception 'payroll export conflict'; end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_export.recorded', 'payroll_batch', p_batch,
    jsonb_build_object('format', v_format, 'count', p_count, 'checksum', v_checksum)
  );
end;
$$;

revoke all on function public.record_payroll_export(uuid,text,text,integer) from public;
grant execute on function public.record_payroll_export(uuid,text,text,integer) to authenticated;

comment on function public.record_payroll_export(uuid,text,text,integer) is
'Finance/Admin-only immutable export finalization. Locks the batch, validates SHA-256 evidence and checks the caller count against database items.';
