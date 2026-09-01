-- Structural regression checks for secure shift discovery.
-- These checks are credential-free and validate that discovery keeps
-- the same core safety invariants as acceptance.

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.get_available_shifts()'::regprocedure) into v_def;

  if position('worker_is_deployable(auth.uid())' in v_def) = 0 then
    raise exception 'get_available_shifts must enforce final live deployability';
  end if;

  if position('mine.cancelled_at is null' in v_def) = 0 then
    raise exception 'get_available_shifts must ignore cancelled assignments';
  end if;

  if position('existing.starts_at < sh.ends_at' in v_def) = 0
     or position('existing.ends_at > sh.starts_at' in v_def) = 0 then
    raise exception 'get_available_shifts must suppress overlapping shifts';
  end if;

  if position('active.cancelled_at is null' in v_def) = 0
     or position('< sh.headcount' in v_def) = 0 then
    raise exception 'get_available_shifts must enforce remaining capacity';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon', 'public.get_available_shifts()', 'EXECUTE') then
    raise exception 'anon must not execute get_available_shifts';
  end if;

  if not has_function_privilege('authenticated', 'public.get_available_shifts()', 'EXECUTE') then
    raise exception 'authenticated must be able to execute get_available_shifts';
  end if;
end;
$$;
