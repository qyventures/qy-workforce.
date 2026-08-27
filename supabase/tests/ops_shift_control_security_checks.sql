-- Structural regression checks for the live Ops shift control boundary.

begin;

do $$
declare
  v_def text;
begin
  if to_regprocedure('public.get_ops_shift_queue(timestamptz,timestamptz)') is null then
    raise exception 'get_ops_shift_queue is missing';
  end if;

  select pg_get_functiondef('public.get_ops_shift_queue(timestamptz,timestamptz)'::regprocedure)
    into v_def;

  if position('security definer' in lower(v_def)) = 0
     or position('public.is_ops()' in v_def) = 0
     or position('auth.uid()' in v_def) = 0 then
    raise exception 'Ops queue must enforce authenticated Ops access inside a security-definer RPC';
  end if;

  if position('cancelled_at is null' in lower(v_def)) = 0 then
    raise exception 'fill count must exclude cancelled assignments';
  end if;

  if position('p_to - p_from > interval ''366 days''' in lower(v_def)) = 0
     or position('p_to <= p_from' in lower(v_def)) = 0 then
    raise exception 'Ops queue must bound and validate its requested date range';
  end if;

  if position('sa.worker_id' in lower(v_def)) > 0 then
    raise exception 'Ops queue must not return or group by worker identity';
  end if;

  if has_function_privilege('anon',
      'public.get_ops_shift_queue(timestamptz,timestamptz)','EXECUTE') then
    raise exception 'anon must not execute the Ops shift queue';
  end if;

  if not has_function_privilege('authenticated',
      'public.get_ops_shift_queue(timestamptz,timestamptz)','EXECUTE') then
    raise exception 'authenticated staff must be able to invoke the authorised RPC';
  end if;
end $$;

rollback;
