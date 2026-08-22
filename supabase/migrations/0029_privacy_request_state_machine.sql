-- QY Workforce: strict, audited privacy-request lifecycle.
-- Builds on 0017 without introducing destructive erasure. Completion remains an
-- administrative evidence state; actual minimisation/deletion is handled separately.

create or replace function public.review_privacy_request(
  p_request uuid,
  p_decision text,
  p_reason text default null,
  p_retention_hold boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid;
  v_type text;
  v_old_status text;
  v_old_hold boolean;
  v_reason text := nullif(trim(coalesce(p_reason,'')), '');
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() <> 'admin' then raise exception 'admin required'; end if;
  if p_decision not in ('in_review','approved','rejected','completed','cancelled') then
    raise exception 'unsupported decision';
  end if;

  select worker_id, request_type, status, retention_hold
    into v_worker, v_type, v_old_status, v_old_hold
  from public.privacy_requests
  where id = p_request
  for update;

  if v_worker is null then raise exception 'privacy request not found'; end if;
  if v_worker = auth.uid() then raise exception 'self-review is not permitted'; end if;
  if v_old_status in ('rejected','completed','cancelled') then
    raise exception 'privacy request is terminal';
  end if;

  -- Explicit state machine prevents bypassing review/approval evidence.
  if not (
    (v_old_status = 'submitted' and p_decision in ('in_review','cancelled')) or
    (v_old_status = 'in_review' and p_decision in ('approved','rejected','cancelled')) or
    (v_old_status = 'approved' and p_decision in ('in_review','completed','cancelled'))
  ) then
    raise exception 'invalid privacy request transition: % -> %', v_old_status, p_decision;
  end if;

  if p_decision in ('rejected','cancelled') and v_reason is null then
    raise exception 'decision reason required';
  end if;

  -- Any legal/operational hold change must carry an auditable rationale.
  if p_retention_hold is distinct from v_old_hold and v_reason is null then
    raise exception 'reason required when changing retention hold';
  end if;

  -- Erasure is never marked completed while evidence is under hold.
  if p_decision = 'completed' and v_type = 'erasure' and p_retention_hold then
    raise exception 'erasure cannot be completed while retention hold is active';
  end if;

  -- Erasure completion requires an explicit administrative rationale/evidence note.
  if p_decision = 'completed' and v_type = 'erasure' and v_reason is null then
    raise exception 'completion reason required for erasure';
  end if;

  update public.privacy_requests
  set status = p_decision,
      retention_hold = p_retention_hold,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      completed_at = case when p_decision = 'completed' then now() else null end,
      decision_reason = case when v_reason is null then decision_reason else left(v_reason,1000) end,
      updated_at = now()
  where id = p_request;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'privacy_request.transitioned', 'privacy_request', p_request,
    jsonb_build_object(
      'request_type', v_type,
      'from_status', v_old_status,
      'to_status', p_decision,
      'retention_hold_before', v_old_hold,
      'retention_hold_after', p_retention_hold
    )
  );
end;
$$;

revoke all on function public.review_privacy_request(uuid,text,text,boolean) from public;
grant execute on function public.review_privacy_request(uuid,text,text,boolean) to authenticated;

comment on function public.review_privacy_request(uuid,text,text,boolean) is
'Admin-only audited privacy-request state machine. Erasure must pass review and approval, cannot complete under retention hold, and requires a completion rationale.';
