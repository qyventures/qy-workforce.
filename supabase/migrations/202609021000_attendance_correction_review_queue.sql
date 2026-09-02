-- Exposes the minimum masked, site-scoped data needed to review attendance
-- corrections. Mutations remain exclusively inside review_attendance_correction.
create or replace function public.get_attendance_correction_review_queue()
returns table (
  request_id uuid,
  assignment_id uuid,
  worker_label text,
  site_name text,
  role_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  requested_clock_in timestamptz,
  requested_clock_out timestamptz,
  reason text,
  requested_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_role public.user_role;
begin
  v_role := public.current_app_role();
  if v_role not in ('supervisor','ops_manager','admin') then
    raise exception 'not authorised';
  end if;

  return query
  select
    acr.id,
    acr.assignment_id,
    'Worker #' || upper(substr(md5(acr.worker_id::text), 1, 6)),
    s.name,
    r.name,
    sh.starts_at,
    sh.ends_at,
    acr.requested_clock_in,
    acr.requested_clock_out,
    acr.reason,
    acr.requested_at
  from public.attendance_correction_requests acr
  join public.shift_assignments a on a.id = acr.assignment_id
  join public.shifts sh on sh.id = a.shift_id
  join public.sites s on s.id = sh.site_id
  join public.roles r on r.id = sh.role_id
  where acr.status = 'pending'
    and (
      v_role in ('ops_manager','admin')
      or exists (
        select 1 from public.supervisor_sites ss
        where ss.supervisor_id = auth.uid() and ss.site_id = sh.site_id
      )
    )
  order by acr.requested_at asc;
end;
$$;

revoke all on function public.get_attendance_correction_review_queue() from public;
grant execute on function public.get_attendance_correction_review_queue() to authenticated;
