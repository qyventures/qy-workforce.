-- Make assignment cancellation an explicit audited state transition.
-- Workers may release a future accepted assignment they own before attendance begins.
-- Ops/Admin may cancel another worker's future assignment only with a rationale.
-- Once any attendance event exists, cancellation is blocked so worked time cannot be
-- hidden or capacity silently reopened; attendance/timesheet correction must be used.

create or replace function public.cancel_shift_assignment(
  p_assignment_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor uuid := auth.uid();
  v_worker uuid;
  v_shift uuid;
  v_starts_at timestamptz;
  v_cancelled_at timestamptz;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
  v_is_ops boolean;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;

  v_is_ops := public.is_ops();

  select a.worker_id, a.shift_id, a.cancelled_at, sh.starts_at
    into v_worker, v_shift, v_cancelled_at, v_starts_at
  from public.shift_assignments a
  join public.shifts sh on sh.id=a.shift_id
  where a.id=p_assignment_id
  for update of a;

  if not found or v_cancelled_at is not null then
    raise exception 'assignment unavailable';
  end if;

  -- Serialize this worker's acceptance/cancellation decisions with accept_shift().
  perform pg_advisory_xact_lock(hashtextextended(v_worker::text, 0));

  if v_actor <> v_worker and not v_is_ops then
    raise exception 'not authorised';
  end if;

  if v_starts_at <= now() then
    raise exception 'started assignments cannot be cancelled';
  end if;

  if exists (
    select 1 from public.time_events e where e.assignment_id=p_assignment_id
  ) then
    raise exception 'assignment with attendance cannot be cancelled';
  end if;

  if v_actor <> v_worker and v_reason is null then
    raise exception 'cancellation reason required';
  end if;

  if v_reason is not null and length(v_reason) > 500 then
    raise exception 'cancellation reason too long';
  end if;

  update public.shift_assignments
  set cancelled_at=now()
  where id=p_assignment_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(
    v_actor,
    'shift_assignment.cancelled',
    'shift_assignment',
    p_assignment_id,
    jsonb_strip_nulls(jsonb_build_object(
      'shift_id', v_shift,
      'worker_self_service', v_actor=v_worker,
      'reason', v_reason
    ))
  );
end;
$$;

revoke all on function public.cancel_shift_assignment(uuid,text) from public;
grant execute on function public.cancel_shift_assignment(uuid,text) to authenticated;

comment on function public.cancel_shift_assignment(uuid,text) is
'Audited assignment cancellation. Workers may cancel their own future assignment before attendance; Ops/Admin may cancel future assignments with a rationale. Any attendance event makes cancellation unavailable.';
