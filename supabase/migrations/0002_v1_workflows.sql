-- QY Workforce V1 operational workflow + security controls
-- Designed to layer on top of 0001_core.sql without weakening existing RLS.

create type public.verification_stage as enum ('pending','passed','failed','manual_review');
create type public.training_status as enum ('assigned','in_progress','passed','failed','expired');
create type public.timesheet_status as enum ('draft','submitted','approved','rejected','payroll_ready');

alter table public.timesheets
  add column status public.timesheet_status not null default 'draft',
  add column submitted_at timestamptz,
  add column rejected_at timestamptz,
  add column rejection_reason text,
  add column payroll_ready_at timestamptz;

create table public.worker_consents (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  purpose text not null check (purpose in ('identity_verification','work_eligibility','location_clocking','communications','analytics')),
  policy_version text not null,
  granted boolean not null,
  recorded_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  source text not null default 'worker_app',
  unique(worker_id,purpose,policy_version,recorded_at)
);

create table public.worker_vetting (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  stage text not null check (stage in ('identity','eligibility','interview','reference','document_review')),
  status public.verification_stage not null default 'pending',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  notes_redacted text,
  created_at timestamptz not null default now()
);

create table public.training_modules (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  role_id uuid references public.roles(id) on delete cascade,
  validity_days integer check(validity_days is null or validity_days > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.worker_training (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  module_id uuid not null references public.training_modules(id) on delete cascade,
  status public.training_status not null default 'assigned',
  assigned_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz,
  evidence_ref text,
  verified_by uuid references public.profiles(id),
  unique(worker_id,module_id)
);

create table public.supervisor_sites (
  supervisor_id uuid not null references public.profiles(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  primary key(supervisor_id,site_id)
);

alter table public.worker_consents enable row level security;
alter table public.worker_vetting enable row level security;
alter table public.worker_training enable row level security;
alter table public.supervisor_sites enable row level security;

create or replace function public.current_app_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_privileged()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() in ('ops_manager','finance','admin','auditor'), false);
$$;

create or replace function public.is_ops()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() in ('ops_manager','admin'), false);
$$;

-- Workers can record and read only their own consent history.
create policy "workers read own consents" on public.worker_consents
for select using (worker_id = auth.uid());
create policy "workers create own consents" on public.worker_consents
for insert with check (worker_id = auth.uid());

create policy "workers read own vetting" on public.worker_vetting
for select using (worker_id = auth.uid());
create policy "workers read own training" on public.worker_training
for select using (worker_id = auth.uid());

-- Privileged staff can operate workforce records. Auditors remain read-only.
create policy "ops read all workers" on public.worker_profiles
for select using (public.is_privileged());
create policy "ops update workers" on public.worker_profiles
for update using (public.is_ops()) with check (public.is_ops());

create policy "ops read vetting" on public.worker_vetting
for select using (public.is_privileged());
create policy "ops manage vetting" on public.worker_vetting
for all using (public.is_ops()) with check (public.is_ops());

create policy "ops read training" on public.worker_training
for select using (public.is_privileged());
create policy "ops manage training" on public.worker_training
for all using (public.is_ops()) with check (public.is_ops());

create policy "ops read assignments" on public.shift_assignments
for select using (public.is_privileged());
create policy "ops manage assignments" on public.shift_assignments
for all using (public.is_ops()) with check (public.is_ops());

create policy "ops read time events" on public.time_events
for select using (public.is_privileged());

create policy "worker create own time event" on public.time_events
for insert with check (
  created_by = auth.uid()
  and exists (
    select 1 from public.shift_assignments a
    where a.id = assignment_id and a.worker_id = auth.uid() and a.cancelled_at is null
  )
);

create policy "ops read timesheets" on public.timesheets
for select using (public.is_privileged());
create policy "ops manage timesheets" on public.timesheets
for all using (public.is_ops()) with check (public.is_ops());

create policy "auditors read audit events" on public.audit_events
for select using (public.current_app_role() in ('auditor','admin'));

-- Never allow clients to calculate geofence status themselves; compute from authoritative site coordinates.
create or replace function public.distance_m(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns numeric
language sql
immutable
as $$
  select 6371000 * 2 * asin(
    sqrt(
      power(sin(radians((lat2-lat1)::double precision)/2),2) +
      cos(radians(lat1::double precision)) * cos(radians(lat2::double precision)) *
      power(sin(radians((lon2-lon1)::double precision)/2),2)
    )
  );
$$;

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
begin
  if p_event_type not in ('clock_in','clock_out','break_start','break_end') then
    raise exception 'unsupported event type';
  end if;
  if p_latitude is null or p_longitude is null then
    raise exception 'location required';
  end if;
  if p_accuracy_m is not null and p_accuracy_m > 250 then
    raise exception 'location accuracy insufficient';
  end if;

  select a.worker_id, s.latitude, s.longitude, s.geofence_radius_m
  into v_worker, v_lat, v_lon, v_radius
  from public.shift_assignments a
  join public.shifts sh on sh.id = a.shift_id
  join public.sites s on s.id = sh.site_id
  where a.id = p_assignment_id and a.cancelled_at is null;

  if v_worker is null or v_worker <> auth.uid() then
    raise exception 'assignment not available';
  end if;
  if v_lat is null or v_lon is null then
    raise exception 'site geofence not configured';
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
    jsonb_build_object('event_type',p_event_type,'within_geofence',v_distance <= v_radius));

  return v_event_id;
end;
$$;

revoke all on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) from public;
grant execute on function public.record_clock_event(uuid,text,numeric,numeric,numeric,text) to authenticated;

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
begin
  select a.worker_id, sh.worker_rate, sh.client_rate
    into v_worker, v_worker_rate, v_client_rate
  from public.shift_assignments a join public.shifts sh on sh.id=a.shift_id
  where a.id=p_assignment_id and a.cancelled_at is null;

  if v_worker <> auth.uid() then raise exception 'assignment not available'; end if;

  select min(occurred_at) filter(where event_type='clock_in'),
         max(occurred_at) filter(where event_type='clock_out')
    into v_in,v_out
  from public.time_events where assignment_id=p_assignment_id;

  if v_in is null or v_out is null or v_out <= v_in then
    raise exception 'complete clock in/out required';
  end if;

  v_minutes := floor(extract(epoch from (v_out-v_in))/60)::integer;

  insert into public.timesheets(assignment_id,payable_minutes,worker_amount,client_amount,status,submitted_at)
  values(
    p_assignment_id,v_minutes,
    round(coalesce(v_worker_rate,0) * v_minutes / 60.0,2),
    round(coalesce(v_client_rate,0) * v_minutes / 60.0,2),
    'submitted',now()
  )
  on conflict(assignment_id) do update set
    payable_minutes=excluded.payable_minutes,
    worker_amount=excluded.worker_amount,
    client_amount=excluded.client_amount,
    status='submitted', submitted_at=now(), updated_at=now(),
    approved_by=null,approved_at=null,rejected_at=null,rejection_reason=null,payroll_ready_at=null
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'timesheet.submitted','timesheet',v_id,jsonb_build_object('payable_minutes',v_minutes));
  return v_id;
end;
$$;

revoke all on function public.submit_timesheet(uuid) from public;
grant execute on function public.submit_timesheet(uuid) to authenticated;

create or replace view public.site_margin_summary as
select
  c.id client_id,c.name client_name,s.id site_id,s.name site_name,
  date_trunc('month',sh.starts_at) month,
  count(t.id) approved_timesheets,
  coalesce(sum(t.client_amount),0) revenue,
  coalesce(sum(t.worker_amount),0) worker_cost,
  coalesce(sum(t.client_amount-t.worker_amount),0) gross_margin,
  case when coalesce(sum(t.client_amount),0)=0 then null
       else round(100*sum(t.client_amount-t.worker_amount)/sum(t.client_amount),2) end gross_margin_pct
from public.timesheets t
join public.shift_assignments a on a.id=t.assignment_id
join public.shifts sh on sh.id=a.shift_id
join public.sites s on s.id=sh.site_id
join public.clients c on c.id=s.client_id
where t.status in ('approved','payroll_ready')
group by c.id,c.name,s.id,s.name,date_trunc('month',sh.starts_at);

revoke all on public.site_margin_summary from public;
grant select on public.site_margin_summary to authenticated;

insert into public.training_modules(code,name,role_id,validity_days)
select 'cleaner_site_safety','Cleaner Site Safety',id,365 from public.roles where code='cleaner'
on conflict(code) do nothing;
insert into public.training_modules(code,name,role_id,validity_days)
select 'fnb_food_hygiene_check','F&B Food Hygiene Verification',id,365 from public.roles where code='fnb_service'
on conflict(code) do nothing;
insert into public.training_modules(code,name,role_id,validity_days)
select 'event_safety','Event Crew Safety',id,365 from public.roles where code='event_crew'
on conflict(code) do nothing;
