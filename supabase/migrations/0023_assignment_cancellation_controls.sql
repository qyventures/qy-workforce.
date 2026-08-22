-- QY Workforce: make assignment cancellation an audited, capacity-safe boundary.
-- Workers may cancel only their own future assignments. Ops may cancel on behalf
-- of a worker, but neither path can erase an assignment after attendance or a
-- timesheet exists. Repeated cancellation is idempotent.

drop policy if exists "ops manage assignments" on public.shift_assignments;
revoke insert, update, delete on public.shift_assignments from authenticated;

create or replace function public.cancel_shift_assignment(
  p_assignment_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_worker uuid;
  v_shift uuid;
  v_starts_at timestamptz;
  v_cancelled_at timestamptz;
  v_is_ops boolean;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if v_reason is null then raise exception 'cancellation reason required'; end if;
  if char_length(v_reason) > 500 then raise exception 'cancellation reason too long'; end if;

  v_is_ops := coalesce(public.is_ops(), false);

  select a.worker_id, a.shift_id, sh.starts_at, a.cancelled_at
    into v_worker, v_shift, v_starts_at, v_cancelled_at
  from public.shift_assignments a
  join public.shifts sh on sh.id = a.shift_id
  where a.id = p_assignment_id
  for update of a, sh;

  if not found then raise exception 'assignment not available'; end if;
  if v_worker <> v_actor and not v_is_ops then raise exception 'not authorised'; end if;
  if v_cancelled_at is not null then return; end if;
  if not v_is_ops and v_starts_at <= now() then
    raise exception 'worker cancellation window closed';
  end if;
  if exists (select 1 from public.time_events where assignment_id = p_assignment_id) then
    raise exception 'assignment with attendance cannot be cancelled';
  end if;
  if exists (select 1 from public.timesheets where assignment_id = p_assignment_id) then
    raise exception 'assignment with timesheet cannot be cancelled';
  end if;

  update public.shift_assignments
     set cancelled_at = now()
   where id = p_assignment_id and cancelled_at is null;

  if not found then return; end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    v_actor,
    'shift_assignment.cancelled',
    'shift_assignment',
    p_assignment_id,
    jsonb_build_object(
      'shift_id', v_shift,
      'worker_self_service', v_worker = v_actor,
      'cancelled_by_ops', v_is_ops and v_worker <> v_actor,
      'reason', v_reason,
      'attendance_checked', true,
      'timesheet_checked', true
    )
  );
end;
$$;

revoke all on function public.cancel_shift_assignment(uuid,text) from public;
grant execute on function public.cancel_shift_assignment(uuid,text) to authenticated;

create index if not exists idx_shift_assignments_active_capacity
  on public.shift_assignments(shift_id)
  where cancelled_at is null;

comment on function public.cancel_shift_assignment(uuid,text) is
'Worker-owner/Ops assignment cancellation with row locking, required reason, attendance/timesheet guards, idempotency and audit evidence.';
