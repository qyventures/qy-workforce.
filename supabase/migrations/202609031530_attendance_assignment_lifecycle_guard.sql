-- QY Workforce: bind worker-app attendance to live demand configuration.
-- Forward-only hardening: clock-out remains available for an active assignment,
-- but cancelled shifts and deactivated client/site records cannot receive new
-- worker-app events. Device identifiers are accepted only as opaque hashes.

create or replace function public.record_clock_event(
  p_assignment_id uuid,
  p_event_type text,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric default null,
  p_device_hash text default null
)
returns uuid
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
  v_last_event timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_event_type not in ('clock_in','clock_out','break_start','break_end') then
    raise exception 'unsupported event type';
  end if;
  if p_latitude is null or p_longitude is null then raise exception 'location required'; end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid coordinates';
  end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 250) then
    raise exception 'location accuracy insufficient';
  end if;
  if p_device_hash is not null and char_length(trim(p_device_hash)) not between 16 and 256 then
    raise exception 'invalid device hash';
  end if;

  select a.worker_id, s.latitude, s.longitude, s.geofence_radius_m,
         sh.starts_at, sh.ends_at
    into v_worker, v_lat, v_lon, v_radius, v_starts, v_ends
  from public.shift_assignments a
  join public.shifts sh on sh.id = a.shift_id
  join public.sites s on s.id = sh.site_id
  join public.clients c on c.id = s.client_id
  where a.id = p_assignment_id
    and a.cancelled_at is null
    and a.accepted_at is not null
    and sh.status <> 'cancelled'
    and s.active
    and c.active;

  if v_worker is null or v_worker <> auth.uid() then raise exception 'assignment not available'; end if;
  if v_lat is null or v_lon is null then raise exception 'site geofence not configured'; end if;
  if now() < v_starts - interval '3 hours' or now() > v_ends + interval '6 hours' then
    raise exception 'attendance event outside permitted shift window';
  end if;

  select max(occurred_at) into v_last_event
  from public.time_events
  where assignment_id = p_assignment_id and created_by = auth.uid();
  if v_last_event is not null and v_last_event > now() - interval '20 seconds' then
    raise exception 'attendance event submitted too quickly';
  end if;

  v_distance := public.distance_m(p_latitude, p_longitude, v_lat, v_lon);

  insert into public.time_events(
    assignment_id, event_type, latitude, longitude, accuracy_m, within_geofence,
    device_fingerprint_hash, source, created_by
  ) values (
    p_assignment_id, p_event_type, p_latitude, p_longitude, p_accuracy_m,
    v_distance <= v_radius, nullif(trim(p_device_hash), ''), 'worker_app', auth.uid()
  ) returning id into v_event_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'time_event.recorded', 'shift_assignment', p_assignment_id,
    jsonb_build_object('event_type', p_event_type,
      'within_geofence', v_distance <= v_radius, 'accuracy_m', p_accuracy_m,
      'device_hash_supplied', p_device_hash is not null));
  return v_event_id;
end;
$$;

-- The seven-argument API is the live boundary: it also enforces mocked-location
-- rejection and creates the draft timesheet. Wrap the existing implementation
-- so those behaviors remain intact while lifecycle checks run first.
do $$
begin
  if to_regprocedure('public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean)') is not null
     and to_regprocedure('public.record_clock_event_attendance_core(uuid,text,numeric,numeric,numeric,text,boolean)') is null then
    alter function public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean)
      rename to record_clock_event_attendance_core;
  end if;
end;
$$;

revoke all on function public.record_clock_event_attendance_core(uuid,text,numeric,numeric,numeric,text,boolean) from public;

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
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_device_hash is not null and char_length(trim(p_device_hash)) not between 16 and 256 then
    raise exception 'invalid device hash';
  end if;
  if not exists (
    select 1
    from public.shift_assignments a
    join public.shifts sh on sh.id = a.shift_id
    join public.sites s on s.id = sh.site_id
    join public.clients c on c.id = s.client_id
    where a.id = p_assignment_id
      and a.worker_id = auth.uid()
      and a.cancelled_at is null
      and a.accepted_at is not null
      and sh.status <> 'cancelled'
      and s.active
      and c.active
  ) then
    raise exception 'assignment not available';
  end if;

  return public.record_clock_event_attendance_core(
    p_assignment_id, p_event_type, p_latitude, p_longitude,
    p_accuracy_m, nullif(trim(p_device_hash), ''), p_is_mocked
  );
end;
$$;

-- Keep the obsolete six-argument overload unavailable; it cannot bypass the
-- mocked-location and timesheet behavior of the live API.
revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) from public;
revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) from authenticated;
grant execute on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean) to authenticated;

comment on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean) is
'Worker-only attendance boundary. Requires an active assignment, live client/site configuration, valid geofence input and an opaque device hash; cancelled demand cannot receive new worker-app events.';
