-- Structural regression checks for assignment cancellation integrity.

do $$
begin
  if to_regprocedure('public.cancel_shift_assignment(uuid,text)') is null then
    raise exception 'cancel_shift_assignment(uuid,text) is missing';
  end if;

  if has_function_privilege('anon','public.cancel_shift_assignment(uuid,text)','EXECUTE') then
    raise exception 'anon must not execute assignment cancellation';
  end if;

  if not has_function_privilege('authenticated','public.cancel_shift_assignment(uuid,text)','EXECUTE') then
    raise exception 'authenticated must execute controlled assignment cancellation';
  end if;
end $$;

-- Verify the function remains SECURITY DEFINER with a fixed search_path and keeps
-- the authorization, timing, attendance, rationale, advisory-lock, and audit guards.
do $$
declare
  v_def text;
  v_prosecdef boolean;
  v_config text[];
begin
  select pg_get_functiondef(p.oid), p.prosecdef, p.proconfig
    into v_def, v_prosecdef, v_config
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='cancel_shift_assignment'
    and pg_get_function_identity_arguments(p.oid)='p_assignment_id uuid, p_reason text';

  if not coalesce(v_prosecdef,false) then
    raise exception 'cancel_shift_assignment must remain SECURITY DEFINER';
  end if;

  if v_config is null or not ('search_path=public'=any(v_config)) then
    raise exception 'cancel_shift_assignment must pin search_path=public';
  end if;

  v_def := lower(v_def);
  if position('public.is_ops()' in v_def)=0
     or position('v_actor <> v_worker' in v_def)=0 then
    raise exception 'cancellation authorization guard missing';
  end if;

  if position('v_starts_at <= now()' in v_def)=0
     or position('public.time_events' in v_def)=0 then
    raise exception 'started/attendance cancellation guard missing';
  end if;

  if position('cancellation reason required' in v_def)=0
     or position('length(v_reason) > 500' in v_def)=0 then
    raise exception 'ops rationale minimisation guard missing';
  end if;

  if position('pg_advisory_xact_lock' in v_def)=0 then
    raise exception 'worker acceptance/cancellation serialization missing';
  end if;

  if position('shift_assignment.cancelled' in v_def)=0
     or position('public.audit_events' in v_def)=0 then
    raise exception 'assignment cancellation audit event missing';
  end if;
end $$;
