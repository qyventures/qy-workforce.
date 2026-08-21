-- QY Workforce V1 attendance + approval hardening

-- Workers need to see their own attendance history to understand why a timesheet can/cannot submit.
create policy "workers read own time events" on public.time_events
for select using (
  exists(
    select 1 from public.shift_assignments a
    where a.id = assignment_id and a.worker_id = auth.uid()
  )
);

create index if not exists idx_assignments_worker_active
  on public.shift_assignments(worker_id, accepted_at)
  where cancelled_at is null;
create index if not exists idx_time_events_assignment_occurred
  on public.time_events(assignment_id, occurred_at);
create index if not exists idx_timesheets_status
  on public.timesheets(status, submitted_at);
create index if not exists idx_shifts_site_starts
  on public.shifts(site_id, starts_at);

-- Prevent duplicate rapid-fire clock events and implausible attendance timing.
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
  if p_event_type not in ('clock_in','clock_out','break_start','break_end') then
    raise exception 'unsupported event type';
  end if;
  if p_latitude is null or p_longitude is null then raise exception 'location required'; end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'invalid coordinates'; end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 250) then raise exception 'location accuracy insufficient'; end if;

  select a.worker_id, s.latitude, s.longitude, s.geofence_radius_m, sh.starts_at, sh.ends_at
  into v_worker, v_lat, v_lon, v_radius, v_starts, v_ends
  from public.shift_assignments a
  join public.shifts sh on sh.id = a.shift_id
  join public.sites s on s.id = sh.site_id
  where a.id = p_assignment_id and a.cancelled_at is null and a.accepted_at is not null;

  if v_worker is null or v_worker <> auth.uid() then raise exception 'assignment not available'; end if;
  if v_lat is null or v_lon is null then raise exception 'site geofence not configured'; end if;
  if now() < v_starts - interval '3 hours' or now() > v_ends + interval '6 hours' then raise exception 'attendance event outside permitted shift window'; end if;

  select max(occurred_at) into v_last_event
  from public.time_events
  where assignment_id = p_assignment_id and created_by = auth.uid();
  if v_last_event is not null and v_last_event > now() - interval '20 seconds' then
    raise exception 'attendance event submitted too quickly';
  end if;

  v_distance := public.distance_m(p_latitude,p_longitude,v_lat,v_lon);

  insert into public.time_events(
    assignment_id,event_type,latitude,longitude,accuracy_m,within_geofence,
    device_fingerprint_hash,source,created_by
  ) values (
    p_assignment_id,p_event_type,p_latitude,p_longitude,p_accuracy_m,
    v_distance <= v_radius,p_device_hash,'worker_app',auth.uid()
  ) returning id into v_event_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'time_event.recorded','shift_assignment',p_assignment_id,
    jsonb_build_object('event_type',p_event_type,'within_geofence',v_distance <= v_radius,'accuracy_m',p_accuracy_m));
  return v_event_id;
end;
$$;

revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) from public;
grant execute on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) to authenticated;

-- Supervisor approval is scoped to assigned sites; ops/admin may approve any site.
create or replace function public.review_timesheet(
  p_timesheet_id uuid,
  p_decision text,
  p_rejection_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_site uuid;
begin
  if p_decision not in ('approve','reject') then raise exception 'unsupported decision'; end if;
  select public.current_app_role() into v_role;

  select sh.site_id into v_site
  from public.timesheets t
  join public.shift_assignments a on a.id=t.assignment_id
  join public.shifts sh on sh.id=a.shift_id
  where t.id=p_timesheet_id and t.status='submitted';
  if v_site is null then raise exception 'submitted timesheet not found'; end if;

  if v_role = 'supervisor' and not exists(
    select 1 from public.supervisor_sites ss where ss.supervisor_id=auth.uid() and ss.site_id=v_site
  ) then raise exception 'site not assigned to supervisor'; end if;
  if v_role not in ('supervisor','ops_manager','admin') then raise exception 'not authorised'; end if;

  if p_decision='approve' then
    update public.timesheets set status='approved',approved_by=auth.uid(),approved_at=now(),rejected_at=null,rejection_reason=null,updated_at=now()
    where id=p_timesheet_id;
  else
    if nullif(trim(p_rejection_reason),'') is null then raise exception 'rejection reason required'; end if;
    update public.timesheets set status='rejected',rejected_at=now(),rejection_reason=left(trim(p_rejection_reason),500),approved_by=null,approved_at=null,updated_at=now()
    where id=p_timesheet_id;
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'timesheet.' || case when p_decision='approve' then 'approved' else 'rejected' end,'timesheet',p_timesheet_id,
    jsonb_build_object('site_id',v_site));
end;
$$;

revoke all on function public.review_timesheet(uuid,text,text) from public;
grant execute on function public.review_timesheet(uuid,text,text) to authenticated;
