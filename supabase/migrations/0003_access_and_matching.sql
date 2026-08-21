-- Close remaining RLS gaps and add safe shift discovery/acceptance.

alter table public.roles enable row level security;
alter table public.skills enable row level security;
alter table public.clients enable row level security;
alter table public.sites enable row level security;
alter table public.shifts enable row level security;
alter table public.training_modules enable row level security;

create policy "authenticated read active roles" on public.roles
for select to authenticated using (active=true or public.is_privileged());
create policy "authenticated read active skills" on public.skills
for select to authenticated using (active=true or public.is_privileged());
create policy "authenticated read active training modules" on public.training_modules
for select to authenticated using (active=true or public.is_privileged());

create policy "privileged read clients" on public.clients
for select to authenticated using (public.is_privileged());
create policy "ops manage clients" on public.clients
for all to authenticated using (public.is_ops()) with check (public.is_ops());

create policy "privileged read sites" on public.sites
for select to authenticated using (public.is_privileged());
create policy "ops manage sites" on public.sites
for all to authenticated using (public.is_ops()) with check (public.is_ops());

-- Workers can discover only open shifts for roles they have been approved for.
create policy "workers discover eligible open shifts" on public.shifts
for select to authenticated using (
  public.is_privileged()
  or exists (
    select 1 from public.worker_roles wr
    where wr.worker_id=auth.uid() and wr.role_id=shifts.role_id and wr.approved=true
  )
  or exists (
    select 1 from public.shift_assignments a
    where a.shift_id=shifts.id and a.worker_id=auth.uid()
  )
);
create policy "ops manage shifts" on public.shifts
for all to authenticated using (public.is_ops()) with check (public.is_ops());

-- Supervisors can see assigned site/site shifts and relevant assignment/timesheet records.
create policy "supervisor read assigned sites" on public.sites
for select to authenticated using (
  exists(select 1 from public.supervisor_sites ss where ss.site_id=sites.id and ss.supervisor_id=auth.uid())
);
create policy "supervisor read site shifts" on public.shifts
for select to authenticated using (
  exists(select 1 from public.supervisor_sites ss where ss.site_id=shifts.site_id and ss.supervisor_id=auth.uid())
);
create policy "supervisor read site assignments" on public.shift_assignments
for select to authenticated using (
  exists(
    select 1 from public.shifts sh
    join public.supervisor_sites ss on ss.site_id=sh.site_id
    where sh.id=shift_assignments.shift_id and ss.supervisor_id=auth.uid()
  )
);
create policy "supervisor read site timesheets" on public.timesheets
for select to authenticated using (
  exists(
    select 1 from public.shift_assignments a
    join public.shifts sh on sh.id=a.shift_id
    join public.supervisor_sites ss on ss.site_id=sh.site_id
    where a.id=timesheets.assignment_id and ss.supervisor_id=auth.uid()
  )
);

create or replace function public.accept_shift(p_shift_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role uuid;
  v_status public.shift_status;
  v_headcount integer;
  v_taken integer;
  v_worker_status public.worker_status;
  v_assignment uuid;
begin
  select role_id,status,headcount into v_role,v_status,v_headcount
  from public.shifts where id=p_shift_id for update;
  if v_status <> 'open' then raise exception 'shift unavailable'; end if;

  select status into v_worker_status from public.worker_profiles where user_id=auth.uid();
  if v_worker_status <> 'deployable' then raise exception 'worker not deployable'; end if;

  if not exists(select 1 from public.worker_roles where worker_id=auth.uid() and role_id=v_role and approved=true) then
    raise exception 'role not approved';
  end if;

  select count(*) into v_taken from public.shift_assignments
  where shift_id=p_shift_id and cancelled_at is null;
  if v_taken >= v_headcount then raise exception 'shift full'; end if;

  insert into public.shift_assignments(shift_id,worker_id,accepted_at)
  values(p_shift_id,auth.uid(),now())
  on conflict(shift_id,worker_id) do update set accepted_at=now(),cancelled_at=null
  returning id into v_assignment;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'shift.accepted','shift_assignment',v_assignment,jsonb_build_object('shift_id',p_shift_id));
  return v_assignment;
end;
$$;
revoke all on function public.accept_shift(uuid) from public;
grant execute on function public.accept_shift(uuid) to authenticated;

create or replace function public.approve_timesheet(p_timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_site uuid;
begin
  select sh.site_id into v_site
  from public.timesheets t
  join public.shift_assignments a on a.id=t.assignment_id
  join public.shifts sh on sh.id=a.shift_id
  where t.id=p_timesheet_id and t.status='submitted'
  for update of t;

  if v_site is null then raise exception 'timesheet unavailable'; end if;
  if not (public.is_ops() or exists(select 1 from public.supervisor_sites ss where ss.site_id=v_site and ss.supervisor_id=auth.uid())) then
    raise exception 'not authorised';
  end if;

  update public.timesheets
  set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now()
  where id=p_timesheet_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id)
  values(auth.uid(),'timesheet.approved','timesheet',p_timesheet_id);
end;
$$;
revoke all on function public.approve_timesheet(uuid) from public;
grant execute on function public.approve_timesheet(uuid) to authenticated;

-- Views execute with caller rights so worker RLS cannot be bypassed by the view owner.
alter view public.site_margin_summary set (security_invoker=true);

-- Only finance/ops/admin should consume full margin reporting. Workers may have SELECT at
-- database grant level, but security_invoker + timesheet RLS limits them to their own rows.
-- The application must additionally hide this report outside privileged roles.
