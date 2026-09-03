-- Structural regression checks for availability-exception lifecycle evidence.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_availability_exceptions'::regclass
      and conname='worker_availability_exceptions_review_evidence_consistency'
      and not convalidated
  ) then
    raise exception 'availability review lifecycle invariant must be a NOT VALID forward-write constraint';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_availability_exceptions'::regclass
      and conname='worker_availability_exceptions_review_pair_consistency'
  ) then
    raise exception 'reviewer and reviewed_at must be recorded as a pair';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_availability_exceptions'::regclass
      and conname='worker_availability_exceptions_cancelled_status_consistency'
  ) then
    raise exception 'cancelled_at must only exist for cancelled exceptions';
  end if;
end;
$$;

do $$
declare v_def text;
begin
  select pg_get_functiondef('public.review_worker_availability_exception(uuid,text,text)'::regprocedure)
    into v_def;
  if position('reviewed_by=auth.uid()' in replace(v_def,' ','')) = 0
     or position('reviewed_at=now()' in replace(v_def,' ','')) = 0 then
    raise exception 'availability review RPC must write reviewer evidence';
  end if;

  select pg_get_functiondef('public.cancel_own_worker_availability_exception(uuid)'::regprocedure)
    into v_def;
  if position('cancelled_at=now()' in replace(v_def,' ','')) = 0 then
    raise exception 'availability cancellation RPC must write cancellation evidence';
  end if;
end;
$$;
