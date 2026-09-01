-- Regression checks: the final deployability status gate cannot drift from matching or clock-in.
begin;

do $$
declare
  v_accept text;
  v_feed text;
  v_assignment_guard text;
  v_clock_guard text;
  v_replacements text;
begin
  select pg_get_functiondef('public.accept_shift(uuid)'::regprocedure) into v_accept;
  select pg_get_functiondef('public.get_available_shifts()'::regprocedure) into v_feed;
  select pg_get_functiondef('public.guard_shift_assignment_activation()'::regprocedure) into v_assignment_guard;
  select pg_get_functiondef('public.guard_worker_clock_in_deployability()'::regprocedure) into v_clock_guard;
  select pg_get_functiondef('public.get_ops_replacement_candidates(uuid,integer)'::regprocedure) into v_replacements;

  if v_accept not ilike '%worker_is_deployable(v_worker)%'
     or v_feed not ilike '%worker_is_deployable(auth.uid())%'
     or v_assignment_guard not ilike '%worker_is_deployable(new.worker_id)%'
     or v_clock_guard not ilike '%worker_is_deployable(v_worker)%' then
    raise exception 'matching and worker clock-in must enforce final deployability';
  end if;
  if v_replacements not ilike '%worker_is_deployable(wp.user_id)%'
     or v_replacements not ilike '%worker_is_available_for_shift(wp.user_id, v_starts, v_ends)%'
     or v_replacements not ilike '%sh.starts_at < v_ends and sh.ends_at > v_starts%' then
    raise exception 'replacement suggestions must align with final readiness, availability and schedule conflicts';
  end if;
  if v_accept ilike '%identity_verified%' or v_feed ilike '%work_eligibility =%'
     or v_assignment_guard ilike '%residency_verified%' or v_clock_guard ilike '%identity_verified%' then
    raise exception 'decision paths must delegate rather than merge independent verification domains';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon', 'public.accept_shift(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.get_available_shifts()', 'EXECUTE')
     or has_function_privilege('anon', 'public.get_ops_replacement_candidates(uuid,integer)', 'EXECUTE') then
    raise exception 'anonymous callers must not execute matching RPCs';
  end if;
  if has_function_privilege('authenticated', 'public.guard_shift_assignment_activation()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.guard_worker_clock_in_deployability()', 'EXECUTE') then
    raise exception 'trigger helpers must not be API-callable';
  end if;
end;
$$;

rollback;
