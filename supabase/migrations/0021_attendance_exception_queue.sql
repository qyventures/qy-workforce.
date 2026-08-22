-- Operations attendance-exception queue. This is deliberately read-only:
-- the existing review_timesheet RPC remains the only approval decision path.

create or replace function public.get_attendance_exception_queue()
returns table (
  timesheet_id uuid,
  worker_label text,
  site_name text,
  role_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  payable_minutes integer,
  exception_type text,
  exception_detail text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
begin
  v_role := public.current_app_role();
  if v_role not in ('supervisor', 'ops_manager', 'admin') then
    raise exception 'not authorised';
  end if;

  return query
  select
    t.id,
    'Worker #' || upper(substr(md5(a.worker_id::text), 1, 6)),
    s.name,
    r.name,
    sh.starts_at,
    sh.ends_at,
    t.payable_minutes,
    case when exists (select 1 from public.time_events te where te.assignment_id = a.id and te.within_geofence = false) then 'Geofence' else 'Duration' end,
    case when exists (select 1 from public.time_events te where te.assignment_id = a.id and te.within_geofence = false) then 'One or more attendance events were recorded outside the configured site radius.' else 'Payable time exceeds the scheduled duration by more than 15 minutes.' end,
    t.submitted_at
  from public.timesheets t
  join public.shift_assignments a on a.id = t.assignment_id
  join public.shifts sh on sh.id = a.shift_id
  join public.sites s on s.id = sh.site_id
  join public.roles r on r.id = sh.role_id
  where t.status = 'submitted'
    and (
      exists (select 1 from public.time_events te where te.assignment_id = a.id and te.within_geofence = false)
      or t.payable_minutes > greatest(0, floor(extract(epoch from (sh.ends_at - sh.starts_at)) / 60)::int + 15)
    )
    and (
      v_role in ('ops_manager', 'admin')
      or exists (select 1 from public.supervisor_sites ss where ss.supervisor_id = auth.uid() and ss.site_id = sh.site_id)
    )
  order by
    case when exists (select 1 from public.time_events te where te.assignment_id = a.id and te.within_geofence = false) then 0 else 1 end,
    t.submitted_at asc;
end;
$$;

revoke all on function public.get_attendance_exception_queue() from public;
grant execute on function public.get_attendance_exception_queue() to authenticated;
