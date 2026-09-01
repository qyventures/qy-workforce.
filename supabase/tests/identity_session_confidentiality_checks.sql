-- Identity-session transport secrets must be inaccessible to authenticated clients.
begin;

do $$
declare
  v_start text;
  v_complete text;
  v_status text;
begin
  if has_table_privilege('authenticated', 'public.identity_provider_sessions', 'SELECT')
     or has_table_privilege('anon', 'public.identity_provider_sessions', 'SELECT') then
    raise exception 'identity session rows must not be directly selectable by API roles';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.identity_provider_sessions'::regclass
      and conname='identity_provider_sessions_provider_environment_check'
  ) then raise exception 'identity provider/environment pairing must have a database constraint'; end if;

  select pg_get_functiondef(p.oid) into v_start
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='start_identity_session';
  if v_start is null
     or v_start not ilike '%invalid provider environment%'
     or v_start not ilike '%p_provider = ''mock'' and p_environment <> ''mock''%'
     or v_start not ilike '%p_provider = ''singpass_myinfo'' and p_environment <> ''staging''%' then
    raise exception 'identity starts must bind mock and staging providers to their environments';
  end if;

  select pg_get_functiondef(p.oid) into v_complete
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='complete_identity_verification_staging';
  if v_complete is null
     or v_complete not ilike '%invalid provider environment%'
     or v_complete not ilike '%v_provider = ''singpass_myinfo'' and v_environment <> ''staging''%' then
    raise exception 'identity completion must reject invalid legacy provider environments';
  end if;

  select pg_get_functiondef(p.oid) into v_status
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_own_identity_session_status';
  if v_status is null or not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_own_identity_session_status' and p.prosecdef
  ) then raise exception 'sanitised identity-session status RPC must be security definer'; end if;
  if v_status ilike '%state_hash%' or v_status ilike '%nonce_hash%' or v_status ilike '%provider_subject_hash%' then
    raise exception 'worker identity status RPC must not expose secrets or correlation hashes';
  end if;

  if not has_function_privilege('authenticated', 'public.get_own_identity_session_status()', 'EXECUTE')
     or has_function_privilege('anon', 'public.get_own_identity_session_status()', 'EXECUTE') then
    raise exception 'only authenticated workers may execute identity-session status RPC';
  end if;
end $$;

rollback;
