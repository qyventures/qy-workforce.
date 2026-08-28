-- Audited Ops cancellation for future shifts. Assignment rows are retained for
-- worker/audit history, but made inactive so attendance cannot begin.
create or replace function public.cancel_shift(p_shift_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_shift public.shifts%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_assignment_count integer;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if v_reason is null or char_length(v_reason) < 10 then raise exception 'cancellation reason must be at least 10 characters'; end if;
  if char_length(v_reason) > 500 then raise exception 'cancellation reason must be 500 characters or fewer'; end if;

  select * into v_shift from public.shifts where id = p_shift_id for update;
  if v_shift.id is null then raise exception 'shift not found'; end if;
  if v_shift.status not in ('draft', 'open') then raise exception 'only draft or open shifts can be cancelled'; end if;
  if v_shift.starts_at <= now() then raise exception 'started shifts cannot be cancelled'; end if;
  if exists (
    select 1 from public.shift_assignments sa
    join public.time_events te on te.assignment_id = sa.id
    where sa.shift_id = p_shift_id
  ) then raise exception 'shift with attendance cannot be cancelled'; end if;

  update public.shift_assignments set cancelled_at = now()
  where shift_id = p_shift_id and cancelled_at is null;
  get diagnostics v_assignment_count = row_count;
  update public.shifts set status = 'cancelled' where id = p_shift_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'shift.cancelled', 'shift', p_shift_id,
    jsonb_build_object('reason', v_reason, 'previous_status', v_shift.status,
      'affected_assignment_count', v_assignment_count, 'starts_at', v_shift.starts_at));
  return p_shift_id;
end;
$$;

revoke all on function public.cancel_shift(uuid,text) from public, anon;
grant execute on function public.cancel_shift(uuid,text) to authenticated;
comment on function public.cancel_shift(uuid,text) is
'Ops-only audited cancellation of future draft/open shifts. Preserves assignment rows, blocks cancellation after attendance, and requires a reason.';
