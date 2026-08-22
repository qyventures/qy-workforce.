-- QY Workforce V1 secure worker attendance + automatic draft timesheet
-- Server-side geofence and event sequencing are authoritative; the mobile client is advisory only.

create or replace function public.get_assignment_attendance_state(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'assignment_id', a.id,
    'shift_id', sh.id,
    'role_name', r.name,
    'site_name', s.name,
    'site_address', s.address,
    'starts_at', sh.starts_at,
    'ends_at', sh.ends_at,
    'worker_rate', sh.worker_rate,
    'clock_in_at', (
      select min(te.occurred_at) from public.time_events te
      where te.assignment_id=a.id and te.event_type='clock_in' and te.within_geofence is true
    ),
    'clock_out_at', (
      select max(te.occurred_at) from public.time_events te
      where te.assignment_id=a.id and te.event_type='clock_out' and te.within_geofence is true
    ),
    'timesheet', (
      select jsonb_build_object(
        'id', t.id,
        'status', t.status,
        'payable_minutes', t.payable_minutes,
        'worker_amount', t.worker_amount,
        'submitted_at', t.submitted_at
      ) from public.timesheets t where t.assignment_id=a.id
    )
  ) into v_result
  from public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  join public.sites s on s.id=sh.site_id
  join public.roles r on r.id=sh.role_id
  where a.id=p_assignment_id
    and a.worker_id=auth.uid()
    and a.accepted_at is not null
    and a.cancelled_at is null;

  if v_result is null then raise exception 'assignment not available'; end if;
  return v_result;
end;
$$;

revoke all on function public.get_assignment_attendance_state(uuid) from public;
grant execute on function public.get_assignment_attendance_state(uuid) to authenticated;

create or replace function public.record_clock_event(
  p_assignment_id uuid,
  p_event_type text,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric default null,
  p_device_hash text default null,
  p_is_mocked boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid;
  v_lat numeric;
  v_lon numeric;
  v_radius integer;
  v_distance numeric;
  v_event_id uuid;
  v_starts timestamptz;
  v_ends timestamptz;
  v_worker_rate numeric;
  v_client_rate numeric;
  v_clock_in timestamptz;
  v_existing_clock_out timestamptz;
  v_last_event timestamptz;
  v_payable_minutes integer;
  v_timesheet_id uuid;
  v_worker_amount numeric(12,2);
  v_client_amount numeric(12,2);
begin
  -- V1 supports one trusted clock-in and one clock-out per assignment.
  if p_event_type not in ('clock_in','clock_out') then raise exception 'unsupported event type'; end if;
  if p_latitude is null or p_longitude is null then raise exception 'location required'; end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'invalid coordinates'; end if;
  if p_accuracy_m is null or p_accuracy_m < 0 or p_accuracy_m > 100 then raise exception 'location accuracy insufficient'; end if;
  if p_is_mocked is true then raise exception 'mocked location is not accepted'; end if;

  select a.worker_id, s.latitude, s.longitude, s.geofence_radius_m,
         sh.starts_at, sh.ends_at, sh.worker_rate, sh.client_rate
  into v_worker, v_lat, v_lon, v_radius, v_starts, v_ends, v_worker_rate, v_client_rate
  from public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  join public.sites s on s.id=sh.site_id
  where a.id=p_assignment_id
    and a.cancelled_at is null
    and a.accepted_at is not null
  for update of a;

  if v_worker is null or v_worker <> auth.uid() then raise exception 'assignment not available'; end if;
  if v_lat is null or v_lon is null or v_radius is null then raise exception 'site geofence not configured'; end if;
  if now() < v_starts - interval '3 hours' or now() > v_ends + interval '6 hours' then
    raise exception 'attendance event outside permitted shift window';
  end if;

  v_distance := public.distance_m(p_latitude,p_longitude,v_lat,v_lon);
  if v_distance > v_radius then
    insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'attendance.geofence_rejected','shift_assignment',p_assignment_id,
      jsonb_build_object('event_type',p_event_type,'distance_m',round(v_distance),'accuracy_m',p_accuracy_m));
    raise exception 'outside approved worksite geofence';
  end if;

  select max(occurred_at) into v_last_event
  from public.time_events
  where assignment_id=p_assignment_id and created_by=auth.uid();
  if v_last_event is not null and v_last_event > now() - interval '20 seconds' then
    raise exception 'attendance event submitted too quickly';
  end if;

  select min(occurred_at) into v_clock_in
  from public.time_events
  where assignment_id=p_assignment_id and event_type='clock_in' and within_geofence is true;
  select max(occurred_at) into v_existing_clock_out
  from public.time_events
  where assignment_id=p_assignment_id and event_type='clock_out' and within_geofence is true;

  if p_event_type='clock_in' and v_clock_in is not null then raise exception 'already clocked in'; end if;
  if p_event_type='clock_out' and v_clock_in is null then raise exception 'clock in required first'; end if;
  if p_event_type='clock_out' and v_existing_clock_out is not null then raise exception 'already clocked out'; end if;

  insert into public.time_events(
    assignment_id,event_type,latitude,longitude,accuracy_m,within_geofence,
    device_fingerprint_hash,source,created_by
  ) values (
    p_assignment_id,p_event_type,p_latitude,p_longitude,p_accuracy_m,true,
    nullif(left(coalesce(p_device_hash,''),128),''),'worker_app',auth.uid()
  ) returning id into v_event_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'time_event.recorded','shift_assignment',p_assignment_id,
    jsonb_build_object('event_type',p_event_type,'within_geofence',true,'accuracy_m',p_accuracy_m));

  if p_event_type='clock_out' then
    -- Draft uses observed attendance minutes. Supervisor approval remains mandatory before payroll readiness.
    v_payable_minutes := greatest(0, floor(extract(epoch from (now()-v_clock_in))/60)::integer);
    -- Defensive ceiling: accepted attendance must never silently create >24 hours of pay.
    if v_payable_minutes > 1440 then raise exception 'attendance duration requires manual review'; end if;
    v_worker_amount := case when v_worker_rate is null then null else round((v_payable_minutes::numeric/60) * v_worker_rate,2) end;
    v_client_amount := case when v_client_rate is null then null else round((v_payable_minutes::numeric/60) * v_client_rate,2) end;

    insert into public.timesheets(assignment_id,payable_minutes,worker_amount,client_amount,status,created_at,updated_at)
    values(p_assignment_id,v_payable_minutes,v_worker_amount,v_client_amount,'draft',now(),now())
    on conflict (assignment_id) do update set
      payable_minutes=excluded.payable_minutes,
      worker_amount=excluded.worker_amount,
      client_amount=excluded.client_amount,
      status=case when public.timesheets.status in ('draft','rejected') then 'draft' else public.timesheets.status end,
      rejected_at=case when public.timesheets.status='rejected' then null else public.timesheets.rejected_at end,
      rejection_reason=case when public.timesheets.status='rejected' then null else public.timesheets.rejection_reason end,
      updated_at=now()
    returning id into v_timesheet_id;

    insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'timesheet.draft_created','timesheet',v_timesheet_id,
      jsonb_build_object('assignment_id',p_assignment_id,'payable_minutes',v_payable_minutes));
  end if;

  return jsonb_build_object(
    'event_id',v_event_id,
    'event_type',p_event_type,
    'distance_m',round(v_distance),
    'occurred_at',now(),
    'timesheet_id',v_timesheet_id,
    'payable_minutes',case when p_event_type='clock_out' then v_payable_minutes else null end,
    'worker_amount',case when p_event_type='clock_out' then v_worker_amount else null end
  );
end;
$$;

-- Remove access to older six-argument overload so clients cannot bypass mocked-location checks.
revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) from public;
revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) from authenticated;
revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean) from public;
grant execute on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean) to authenticated;
