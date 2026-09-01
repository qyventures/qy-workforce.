-- QY Workforce: audited attendance correction requests and controlled approval.
-- Workers may request a correction for their own assignment. Supervisors may review only assigned sites;
-- Ops/admin may review globally. Approved changes never rewrite raw worker clock events: they append
-- supervisor_adjustment evidence and update only draft/rejected timesheets.

create table if not exists public.attendance_correction_requests (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.shift_assignments(id) on delete restrict,
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  requested_clock_in timestamptz,
  requested_clock_out timestamptz,
  reason text not null check (char_length(reason) between 5 and 1000),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by uuid not null references public.profiles(id),
  requested_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text check (review_note is null or char_length(review_note) <= 1000),
  approved_payable_minutes integer check (approved_payable_minutes is null or approved_payable_minutes between 0 and 1440),
  check (requested_clock_in is not null or requested_clock_out is not null),
  check (requested_clock_in is null or requested_clock_out is null or requested_clock_out > requested_clock_in)
);

create unique index if not exists attendance_correction_one_pending_per_assignment
  on public.attendance_correction_requests(assignment_id) where status='pending';
create index if not exists attendance_correction_queue_idx
  on public.attendance_correction_requests(status, requested_at desc);

alter table public.attendance_correction_requests enable row level security;
revoke insert, update, delete on public.attendance_correction_requests from anon, authenticated;

create policy "workers read own attendance correction requests"
on public.attendance_correction_requests for select to authenticated
using (worker_id = auth.uid() or public.is_privileged());

create or replace function public.request_attendance_correction(
  p_assignment_id uuid,
  p_requested_clock_in timestamptz,
  p_requested_clock_out timestamptz,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_worker uuid;
  v_starts timestamptz;
  v_ends timestamptz;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null or char_length(trim(p_reason)) < 5 then
    raise exception 'reason required';
  end if;
  if p_requested_clock_in is null and p_requested_clock_out is null then
    raise exception 'at least one corrected timestamp required';
  end if;

  select a.worker_id, sh.starts_at, sh.ends_at
    into v_worker, v_starts, v_ends
  from public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  where a.id=p_assignment_id;

  if v_worker is null then raise exception 'assignment not found'; end if;
  if v_worker <> auth.uid() and not public.is_ops() then raise exception 'not authorised'; end if;
  if p_requested_clock_in is not null and (p_requested_clock_in < v_starts - interval '6 hours' or p_requested_clock_in > v_ends + interval '6 hours') then
    raise exception 'requested clock-in outside reviewable window';
  end if;
  if p_requested_clock_out is not null and (p_requested_clock_out < v_starts - interval '6 hours' or p_requested_clock_out > v_ends + interval '12 hours') then
    raise exception 'requested clock-out outside reviewable window';
  end if;

  insert into public.attendance_correction_requests(
    assignment_id,worker_id,requested_clock_in,requested_clock_out,reason,requested_by
  ) values (
    p_assignment_id,v_worker,p_requested_clock_in,p_requested_clock_out,trim(p_reason),auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.correction_requested','attendance_correction_request',v_id,
    jsonb_build_object('assignment_id',p_assignment_id,'worker_id',v_worker));
  return v_id;
end $$;

create or replace function public.review_attendance_correction(
  p_request_id uuid,
  p_decision text,
  p_review_note text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_req public.attendance_correction_requests%rowtype;
  v_site uuid;
  v_role public.user_role;
  v_clock_in timestamptz;
  v_clock_out timestamptz;
  v_minutes integer;
  v_worker_rate numeric;
  v_client_rate numeric;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approve','reject') then raise exception 'invalid decision'; end if;

  select * into v_req from public.attendance_correction_requests where id=p_request_id for update;
  if not found then raise exception 'request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'request is not pending'; end if;
  if v_req.requested_by = auth.uid() then raise exception 'requester cannot review own request'; end if;

  select p.role, sh.site_id, sh.worker_rate, sh.client_rate
    into v_role, v_site, v_worker_rate, v_client_rate
  from public.profiles p
  cross join public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  where p.id=auth.uid() and a.id=v_req.assignment_id;

  if v_role is null then raise exception 'reviewer profile not found'; end if;
  if v_role='supervisor'::public.user_role then
    if not exists(select 1 from public.supervisor_sites ss where ss.supervisor_id=auth.uid() and ss.site_id=v_site) then
      raise exception 'supervisor not assigned to site';
    end if;
  elsif v_role not in ('ops_manager'::public.user_role,'admin'::public.user_role) then
    raise exception 'not authorised';
  end if;

  if p_decision='reject' then
    update public.attendance_correction_requests
       set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_review_note),'')
     where id=p_request_id;
    insert into public.audit_events(actor_id,action,entity_type,entity_id)
    values(auth.uid(),'attendance.correction_rejected','attendance_correction_request',p_request_id);
    return;
  end if;

  select coalesce(v_req.requested_clock_in,
      (select min(te.occurred_at) from public.time_events te where te.assignment_id=v_req.assignment_id and te.event_type='clock_in' and te.within_geofence is true)),
         coalesce(v_req.requested_clock_out,
      (select max(te.occurred_at) from public.time_events te where te.assignment_id=v_req.assignment_id and te.event_type='clock_out' and te.within_geofence is true))
    into v_clock_in,v_clock_out;

  if v_clock_in is null or v_clock_out is null or v_clock_out <= v_clock_in then
    raise exception 'complete valid attendance interval required';
  end if;
  v_minutes := floor(extract(epoch from (v_clock_out-v_clock_in))/60)::integer;
  if v_minutes < 0 or v_minutes > 1440 then raise exception 'corrected duration requires manual escalation'; end if;

  if exists(select 1 from public.timesheets t where t.assignment_id=v_req.assignment_id and t.status not in ('draft','rejected')) then
    raise exception 'approved/submitted timesheet must be handled through payroll adjustment workflow';
  end if;

  insert into public.time_events(assignment_id,event_type,occurred_at,within_geofence,source,created_by)
  values(v_req.assignment_id,'supervisor_adjustment',now(),null,'attendance_correction',auth.uid());

  insert into public.timesheets(assignment_id,payable_minutes,worker_amount,client_amount,status,created_at,updated_at)
  values(v_req.assignment_id,v_minutes,
    case when v_worker_rate is null then null else round((v_minutes::numeric/60)*v_worker_rate,2) end,
    case when v_client_rate is null then null else round((v_minutes::numeric/60)*v_client_rate,2) end,
    'draft',now(),now())
  on conflict (assignment_id) do update set
    payable_minutes=excluded.payable_minutes,
    worker_amount=excluded.worker_amount,
    client_amount=excluded.client_amount,
    status='draft',
    rejected_at=null,
    rejection_reason=null,
    updated_at=now();

  update public.attendance_correction_requests
     set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_review_note),''),approved_payable_minutes=v_minutes
   where id=p_request_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'attendance.correction_approved','attendance_correction_request',p_request_id,
    jsonb_build_object('assignment_id',v_req.assignment_id,'approved_payable_minutes',v_minutes));
end $$;

create or replace function public.cancel_own_attendance_correction(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.attendance_correction_requests
     set status='cancelled', reviewed_at=now(), review_note='cancelled by requester'
   where id=p_request_id and status='pending' and requested_by=auth.uid();
  if not found then raise exception 'pending request not found or not owned by requester'; end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id)
  values(auth.uid(),'attendance.correction_cancelled','attendance_correction_request',p_request_id);
end $$;

revoke all on function public.request_attendance_correction(uuid,timestamptz,timestamptz,text) from public;
revoke all on function public.review_attendance_correction(uuid,text,text) from public;
revoke all on function public.cancel_own_attendance_correction(uuid) from public;
grant execute on function public.request_attendance_correction(uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.review_attendance_correction(uuid,text,text) to authenticated;
grant execute on function public.cancel_own_attendance_correction(uuid) to authenticated;
