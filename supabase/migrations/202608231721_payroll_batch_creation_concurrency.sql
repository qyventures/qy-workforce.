-- QY Workforce: serialize payroll batch creation to prevent duplicate active membership.
--
-- The earlier NOT EXISTS check is correct for sequential callers but can race when
-- two finance users create overlapping batches concurrently. A transaction-scoped
-- advisory lock serializes only the short batch-construction critical section.

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
  if p_end - p_start > 62 then
    raise exception 'pay period too large';
  end if;

  -- Payroll batch creation is low-frequency and financially sensitive. Serializing
  -- this critical section prevents two concurrent transactions from both observing
  -- the same approved timesheet as unbatched and inserting it into separate drafts.
  perform pg_advisory_xact_lock(hashtextextended('qy-workforce:payroll-batch-create', 0));

  insert into public.payroll_batches(period_start, period_end, created_by)
  values (p_start, p_end, auth.uid())
  returning id into v_batch;

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

  select count(*) into v_item_count
  from public.payroll_batch_items
  where payroll_batch_id = v_batch;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_batch.created', 'payroll_batch', v_batch,
    jsonb_build_object(
      'period_start', p_start,
      'period_end', p_end,
      'item_count', v_item_count
    )
  );

  return v_batch;
end;
$$;

revoke all on function public.create_payroll_batch(date,date) from public;
grant execute on function public.create_payroll_batch(date,date) to authenticated;

comment on function public.create_payroll_batch(date,date) is
'Creates a draft payroll batch under a transaction-scoped advisory lock so concurrent finance callers cannot place one timesheet into multiple active payroll workflows.';
