-- QY Workforce V1: harden timesheet review against concurrent decisions and self-approval.

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
  v_worker uuid;
  v_status text;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'unsupported decision';
  end if;

  select public.current_app_role() into v_role;
  if v_role not in ('supervisor','ops_manager','admin') then
    raise exception 'not authorised';
  end if;

  -- Lock the submitted timesheet before authorization and transition so two
  -- reviewers cannot both make a valid decision or emit duplicate audit trails.
  select sh.site_id, a.worker_id, t.status::text
  into v_site, v_worker, v_status
  from public.timesheets t
  join public.shift_assignments a on a.id=t.assignment_id
  join public.shifts sh on sh.id=a.shift_id
  where t.id=p_timesheet_id
  for update of t;

  if v_site is null then
    raise exception 'timesheet not found';
  end if;
  if v_status <> 'submitted' then
    raise exception 'timesheet is no longer awaiting review';
  end if;

  -- Separation of duties: no reviewer may approve/reject their own worker timesheet.
  if v_worker = auth.uid() then
    raise exception 'self review is not permitted';
  end if;

  if v_role = 'supervisor' and not exists(
    select 1 from public.supervisor_sites ss
    where ss.supervisor_id=auth.uid() and ss.site_id=v_site
  ) then
    raise exception 'site not assigned to supervisor';
  end if;

  if p_decision='approve' then
    update public.timesheets
    set status='approved',
        approved_by=auth.uid(),
        approved_at=now(),
        rejected_at=null,
        rejection_reason=null,
        updated_at=now()
    where id=p_timesheet_id and status='submitted';
  else
    if nullif(trim(p_rejection_reason),'') is null then
      raise exception 'rejection reason required';
    end if;
    update public.timesheets
    set status='rejected',
        rejected_at=now(),
        rejection_reason=left(trim(p_rejection_reason),500),
        approved_by=null,
        approved_at=null,
        updated_at=now()
    where id=p_timesheet_id and status='submitted';
  end if;

  if not found then
    raise exception 'timesheet review conflict';
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    'timesheet.' || case when p_decision='approve' then 'approved' else 'rejected' end,
    'timesheet',
    p_timesheet_id,
    jsonb_build_object('site_id',v_site,'decision',p_decision)
  );
end;
$$;

revoke all on function public.review_timesheet(uuid,text,text) from public;
grant execute on function public.review_timesheet(uuid,text,text) to authenticated;
