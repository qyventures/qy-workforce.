-- QY Workforce: attendance anomaly detection and review controls.
-- This is deliberately non-blocking: authoritative geofence/event validation remains in record_clock_event().
-- Suspicious accepted events are queued for privileged review without exposing raw location/device identifiers.

create table public.attendance_anomalies (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.time_events(id) on delete cascade,
  assignment_id uuid not null references public.shift_assignments(id) on delete cascade,
  reason text not null check (reason in ('device_reuse','low_location_confidence','edge_of_geofence','unusual_shift_window')),
  severity text not null check (severity in ('low','medium','high')),
  status text not null default 'open' check (status in ('open','dismissed','confirmed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note_redacted text,
  unique(event_id, reason)
);

alter table public.attendance_anomalies enable row level security;

create policy "privileged read attendance anomalies" on public.attendance_anomalies
for select to authenticated using (public.is_privileged());

-- No direct insert/update/delete policy: anomaly creation is trigger-owned and review is RPC-only.
revoke insert, update, delete on public.attendance_anomalies from authenticated;

create or replace function public.detect_attendance_anomalies()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_worker uuid;
  v_site_lat numeric;
  v_site_lon numeric;
  v_radius integer;
  v_starts timestamptz;
  v_ends timestamptz;
  v_distance numeric;
  v_anomaly_id uuid;
begin
  -- Only worker-app clock events are scored. Supervisor adjustments remain separately audited workflows.
  if new.source <> 'worker_app' or new.event_type not in ('clock_in','clock_out') then
    return new;
  end if;

  select a.worker_id, s.latitude, s.longitude, s.geofence_radius_m, sh.starts_at, sh.ends_at
    into v_worker, v_site_lat, v_site_lon, v_radius, v_starts, v_ends
  from public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  join public.sites s on s.id=sh.site_id
  where a.id=new.assignment_id;

  if v_worker is null then return new; end if;

  -- A fingerprint appearing for different workers in a short window is a fraud signal.
  -- The fingerprint itself is deliberately not copied into anomaly metadata.
  if nullif(new.device_fingerprint_hash,'') is not null and exists (
    select 1
    from public.time_events te
    join public.shift_assignments a2 on a2.id=te.assignment_id
    where te.id<>new.id
      and te.device_fingerprint_hash=new.device_fingerprint_hash
      and a2.worker_id<>v_worker
      and te.created_at >= now()-interval '12 hours'
  ) then
    insert into public.attendance_anomalies(event_id,assignment_id,reason,severity,metadata)
    values(new.id,new.assignment_id,'device_reuse','high',jsonb_build_object('window_hours',12))
    on conflict(event_id,reason) do nothing
    returning id into v_anomaly_id;

    if v_anomaly_id is not null then
      insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
      values(new.created_by,'attendance.anomaly_created','attendance_anomaly',v_anomaly_id,
        jsonb_build_object('reason','device_reuse','severity','high'));
    end if;
  end if;

  -- record_clock_event permits <=100m accuracy. Values over 50m are accepted but reviewed.
  if new.accuracy_m is not null and new.accuracy_m > 50 then
    v_anomaly_id:=null;
    insert into public.attendance_anomalies(event_id,assignment_id,reason,severity,metadata)
    values(new.id,new.assignment_id,'low_location_confidence','medium',jsonb_build_object('accuracy_band','50_to_100m'))
    on conflict(event_id,reason) do nothing
    returning id into v_anomaly_id;

    if v_anomaly_id is not null then
      insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
      values(new.created_by,'attendance.anomaly_created','attendance_anomaly',v_anomaly_id,
        jsonb_build_object('reason','low_location_confidence','severity','medium'));
    end if;
  end if;

  -- Events near the configured edge are valid, but useful for targeted review when patterns repeat.
  if new.latitude is not null and new.longitude is not null and v_site_lat is not null and v_site_lon is not null and v_radius is not null then
    v_distance:=public.distance_m(new.latitude,new.longitude,v_site_lat,v_site_lon);
    if v_distance > (v_radius * 0.80) then
      v_anomaly_id:=null;
      insert into public.attendance_anomalies(event_id,assignment_id,reason,severity,metadata)
      values(new.id,new.assignment_id,'edge_of_geofence','low',jsonb_build_object('distance_band','80_to_100_percent_radius'))
      on conflict(event_id,reason) do nothing
      returning id into v_anomaly_id;

      if v_anomaly_id is not null then
        insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
        values(new.created_by,'attendance.anomaly_created','attendance_anomaly',v_anomaly_id,
          jsonb_build_object('reason','edge_of_geofence','severity','low'));
      end if;
    end if;
  end if;

  -- The attendance RPC intentionally allows a broad recovery window. Flag events well outside normal operations.
  if (new.event_type='clock_in' and new.occurred_at < v_starts-interval '45 minutes')
     or (new.event_type='clock_out' and new.occurred_at > v_ends+interval '2 hours') then
    v_anomaly_id:=null;
    insert into public.attendance_anomalies(event_id,assignment_id,reason,severity,metadata)
    values(new.id,new.assignment_id,'unusual_shift_window','medium',jsonb_build_object('event_type',new.event_type))
    on conflict(event_id,reason) do nothing
    returning id into v_anomaly_id;

    if v_anomaly_id is not null then
      insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
      values(new.created_by,'attendance.anomaly_created','attendance_anomaly',v_anomaly_id,
        jsonb_build_object('reason','unusual_shift_window','severity','medium'));
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.detect_attendance_anomalies() from public;

create trigger trg_detect_attendance_anomalies
after insert on public.time_events
for each row execute function public.detect_attendance_anomalies();

create or replace function public.review_attendance_anomaly(
  p_anomaly_id uuid,
  p_outcome text,
  p_note_redacted text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_current_status text;
  v_assignment uuid;
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_outcome not in ('dismissed','confirmed') then raise exception 'invalid review outcome'; end if;
  if p_note_redacted is not null and length(p_note_redacted)>500 then raise exception 'review note too long'; end if;

  select status,assignment_id into v_current_status,v_assignment
  from public.attendance_anomalies
  where id=p_anomaly_id
  for update;

  if v_current_status is null then raise exception 'attendance anomaly unavailable'; end if;
  if v_current_status <> 'open' then raise exception 'attendance anomaly already reviewed'; end if;

  update public.attendance_anomalies
  set status=p_outcome,
      reviewed_by=auth.uid(),
      reviewed_at=now(),
      review_note_redacted=nullif(trim(p_note_redacted),'')
  where id=p_anomaly_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.anomaly_reviewed','attendance_anomaly',p_anomaly_id,
    jsonb_build_object('outcome',p_outcome,'assignment_id',v_assignment));
end;
$$;

revoke all on function public.review_attendance_anomaly(uuid,text,text) from public;
grant execute on function public.review_attendance_anomaly(uuid,text,text) to authenticated;

create index if not exists idx_attendance_anomalies_open
  on public.attendance_anomalies(status,severity,created_at desc)
  where status='open';
create index if not exists idx_time_events_device_recent
  on public.time_events(device_fingerprint_hash,created_at desc)
  where device_fingerprint_hash is not null;
