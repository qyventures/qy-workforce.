-- QY Workforce: make worker timesheet submission monotonic and attendance-derived.
-- Prevents a worker retry from resetting an approved/payroll-ready timesheet back to submitted.

create or replace function public.submit_timesheet(p_assignment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid;
  v_in timestamptz;
  v_out timestamptz;
  v_minutes integer;
  v_worker_rate numeric;
  v_client_rate numeric;
  v_id uuid;
  v_status public.timesheet_status;
begin
  -- Serialize against cancellation and other assignment-sensitive transitions.
  select a.worker_id, sh.worker_rate, sh.client_rate
    into v_worker, v_worker_rate, v_client_rate
  from public.shift_assignments a
  join public.shifts sh on sh.id = a.shift_id
  where a.id = p_assignment_id
    and a.accepted_at is not null
    and a.cancelled_at is null
  for update of a;

  if v_worker is null or v_worker <> auth.uid() then
    raise exception 'assignment not available';
  end if;

  -- Serialize retries/reviews on the single assignment timesheet.
  select t.id, t.status
    into v_id, v_status
  from public.timesheets t
  where t.assignment_id = p_assignment_id
  for update;

  -- A network retry after a successful submission is idempotent.
  if v_status = 'submitted' then
    return v_id;
  end if;

  -- Worker submission must never unwind supervisor or payroll state.
  if v_status in ('approved','payroll_ready') then
    raise exception 'timesheet already approved or payroll ready';
  end if;

  -- Only server-accepted worker-app attendance is authoritative for payable time.
  select
    min(te.occurred_at) filter(where te.event_type = 'clock_in'),
    max(te.occurred_at) filter(where te.event_type = 'clock_out')
    into v_in, v_out
  from public.time_events te
  where te.assignment_id = p_assignment_id
    and te.within_geofence is true
    and te.source = 'worker_app'
    and te.created_by = v_worker;

  if v_in is null or v_out is null or v_out <= v_in then
    raise exception 'complete trusted clock in/out required';
  end if;

  v_minutes := floor(extract(epoch from (v_out - v_in)) / 60)::integer;
  if v_minutes < 0 or v_minutes > 1440 then
    raise exception 'attendance duration requires manual review';
  end if;

  if v_id is null then
    insert into public.timesheets(
      assignment_id, payable_minutes, worker_amount, client_amount,
      status, submitted_at, created_at, updated_at
    ) values (
      p_assignment_id,
      v_minutes,
      round(coalesce(v_worker_rate,0) * v_minutes / 60.0, 2),
      round(coalesce(v_client_rate,0) * v_minutes / 60.0, 2),
      'submitted', now(), now(), now()
    ) returning id into v_id;
  else
    -- Only draft/rejected timesheets may re-enter submitted state.
    update public.timesheets
    set payable_minutes = v_minutes,
        worker_amount = round(coalesce(v_worker_rate,0) * v_minutes / 60.0, 2),
        client_amount = round(coalesce(v_client_rate,0) * v_minutes / 60.0, 2),
        status = 'submitted',
        submitted_at = now(),
        approved_by = null,
        approved_at = null,
        rejected_at = null,
        rejection_reason = null,
        payroll_ready_at = null,
        updated_at = now()
    where id = v_id
      and status in ('draft','rejected');

    if not found then
      raise exception 'timesheet cannot be submitted from current state';
    end if;
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(
    auth.uid(), 'timesheet.submitted', 'timesheet', v_id,
    jsonb_build_object('assignment_id', p_assignment_id, 'payable_minutes', v_minutes)
  );

  return v_id;
end;
$$;

revoke all on function public.submit_timesheet(uuid) from public;
grant execute on function public.submit_timesheet(uuid) to authenticated;
