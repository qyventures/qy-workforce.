-- Structural regression checks for the identity-session lifecycle boundary.
begin;

do $$
declare
  v_constraint text;
  v_guard text;
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.identity_provider_sessions'::regclass
      and conname = 'identity_provider_sessions_lifecycle_data_check'
  ) then
    raise exception 'identity session lifecycle data must be protected by a database constraint';
  end if;

  select pg_get_constraintdef(oid) into v_constraint
  from pg_constraint
  where conrelid = 'public.identity_provider_sessions'::regclass
    and conname = 'identity_provider_sessions_lifecycle_data_check';
  if v_constraint is null
     or v_constraint not ilike '%expires_at > created_at%'
     or v_constraint not ilike '%status = ''completed''%'
     or v_constraint not ilike '%provider_subject_hash is not null%'
     or v_constraint not ilike '%status = ''failed''%'
     or v_constraint not ilike '%error_code%' then
    raise exception 'identity session terminal-state data contract is incomplete';
  end if;

  select pg_get_functiondef('public.guard_identity_provider_session_transition()'::regprocedure)
    into v_guard;
  if v_guard is null
     or v_guard not ilike '%identity session transport fields are immutable%'
     or v_guard not ilike '%old.status = ''initiated'' and new.status in (''callback_received'', ''failed'', ''expired'')%'
     or v_guard not ilike '%old.status = ''callback_received'' and new.status in (''completed'', ''failed'', ''expired'')%'
     or v_guard not ilike '%invalid identity session state transition%' then
    raise exception 'identity sessions must use the restricted lifecycle state machine';
  end if;

  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'identity_provider_sessions'
      and t.tgname = 'identity_provider_sessions_transition_guard'
      and not t.tgisinternal
  ) then
    raise exception 'identity session transition guard trigger is required';
  end if;

  if has_function_privilege('anon', 'public.guard_identity_provider_session_transition()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.guard_identity_provider_session_transition()', 'EXECUTE') then
    raise exception 'identity session transition guard must not be executable by API roles';
  end if;
end;
$$;

rollback;
