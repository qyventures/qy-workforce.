-- Bridge approved attendance corrections into the existing worker submission flow.
-- Correction requests remain the only source for adjusted endpoints; raw worker
-- clock events remain the source for endpoints that were not corrected.

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

  select t.id, t.status
    into v_id, v_status
  from public.timesheets t
  where t.assignment_id = p_assignment_id
  for update;

  if v_status = 'submitted' then
    return v_id;
  end if;

  if v_status in ('approved','payroll_ready') then
    raise exception 'timesheet already approved or payroll ready';
  end if;

  -- A reviewed correction is authoritative for only the endpoint(s) it changes.
  -- This preserves the raw-event requirement for ordinary attendance while making
  -- the approved correction usable by the worker's normal submission path.
  select
    coalesce(
      (select acr.requested_clock_in
       from public.attendance_correction_requests acr
       where acr.assignment_id = p_assignment_id and acr.status = 'approved'
         and acr.requested_clock_in is not null
       order by acr.reviewed_at desc nulls last, acr.requested_at desc
       limit 1),
      (select min(te.occurred_at) from public.time_events te
       where te.assignment_id = p_assignment_id
         and te.event_type = 'clock_in'
         and te.within_geofence is true
         and te.source = 'worker_app'
         and te.created_by = v_worker)
  ),
  coalesce(
      (select acr.requested_clock_out
       from public.attendance_correction_requests acr
       where acr.assignment_id = p_assignment_id and acr.status = 'approved'
         and acr.requested_clock_out is not null
       order by acr.reviewed_at desc nulls last, acr.requested_at desc
       limit 1),
      (select max(te.occurred_at) from public.time_events te
       where te.assignment_id = p_assignment_id
         and te.event_type = 'clock_out'
         and te.within_geofence is true
         and te.source = 'worker_app'
         and te.created_by = v_worker)
  )
  into v_in, v_out;

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
      p_assignment_id, v_minutes,
      round(coalesce(v_worker_rate,0) * v_minutes / 60.0, 2),
      round(coalesce(v_client_rate,0) * v_minutes / 60.0, 2),
      'submitted', now(), now(), now()
    ) returning id into v_id;
  else
    update public.timesheets
    set payable_minutes = v_minutes,
        worker_amount = round(coalesce(v_worker_rate,0) * v_minutes / 60.0, 2),
        client_amount = round(coalesce(v_client_rate,0) * v_minutes / 60.0, 2),
        status = 'submitted', submitted_at = now(), approved_by = null,
        approved_at = null, rejected_at = null, rejection_reason = null,
        payroll_ready_at = null, updated_at = now()
    where id = v_id and status in ('draft','rejected');

    if not found then
      raise exception 'timesheet cannot be submitted from current state';
    end if;
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'timesheet.submitted', 'timesheet', v_id,
    jsonb_build_object('assignment_id', p_assignment_id, 'payable_minutes', v_minutes,
      'attendance_basis', case when exists (
        select 1 from public.attendance_correction_requests acr
        where acr.assignment_id = p_assignment_id and acr.status = 'approved'
      ) then 'approved_correction_or_raw_events' else 'raw_events' end));

  return v_id;
end;
$$;

revoke all on function public.submit_timesheet(uuid) from public;
grant execute on function public.submit_timesheet(uuid) to authenticated;
