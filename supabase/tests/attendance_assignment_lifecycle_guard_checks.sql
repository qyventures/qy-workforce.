-- Structural regression checks for assignment/demand lifecycle attendance guard.

do $$
declare v_def text;
begin
  select pg_get_functiondef(
    'public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean)'::regprocedure
  ) into v_def;

  if position('auth.uid() is null' in lower(v_def)) = 0 then
    raise exception 'clock event RPC must reject anonymous callers';
  end if;
  if position('sh.status <> ''cancelled''' in lower(v_def)) = 0
     or position('s.active' in lower(v_def)) = 0
     or position('c.active' in lower(v_def)) = 0 then
    raise exception 'clock event RPC must require non-cancelled shifts and active site/client';
  end if;
  if position('invalid device hash' in lower(v_def)) = 0
     or position('nullif(trim(p_device_hash)' in lower(v_def)) = 0 then
    raise exception 'device identifiers must be bounded opaque hashes';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'record_clock_event'
      and pg_get_function_identity_arguments(p.oid) =
        'p_assignment_id uuid, p_event_type text, p_latitude numeric, p_longitude numeric, p_accuracy_m numeric, p_device_hash text, p_is_mocked boolean'
      and p.prosecdef
  ) then
    raise exception 'live attendance wrapper must remain SECURITY DEFINER';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.record_clock_event_attendance_core(uuid,text,numeric,numeric,numeric,text,boolean)',
    'EXECUTE'
  ) then
    raise exception 'attendance core must not be directly executable by clients';
  end if;
end $$;

do $$
begin
  if not has_function_privilege(
    'authenticated',
    'public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean)',
    'EXECUTE'
  ) then
    raise exception 'authenticated attendance RPC grant must remain available';
  end if;
  if has_function_privilege(
    'anon',
    'public.record_clock_event(uuid,text,numeric,numeric,numeric,text,boolean)',
    'EXECUTE'
  ) then
    raise exception 'anonymous callers must not execute attendance RPC';
  end if;
end $$;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'public.record_clock_event(uuid,text,numeric,numeric,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'obsolete six-argument attendance overload must remain revoked';
  end if;
end $$;
