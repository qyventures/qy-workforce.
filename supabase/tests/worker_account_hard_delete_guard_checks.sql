-- Security regression checks for worker hard-delete protection.

do $$
declare
  v_trigger_count integer;
  v_fn_security boolean;
  v_fn_search_path text;
begin
  if has_table_privilege('authenticated', 'public.profiles', 'DELETE') then
    raise exception 'authenticated must not have DELETE on public.profiles';
  end if;

  if has_table_privilege('authenticated', 'public.worker_profiles', 'DELETE') then
    raise exception 'authenticated must not have DELETE on public.worker_profiles';
  end if;

  if has_table_privilege('anon', 'public.profiles', 'DELETE') then
    raise exception 'anon must not have DELETE on public.profiles';
  end if;

  select count(*)
    into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'profiles'
    and t.tgname = 'trg_prevent_worker_profile_hard_delete'
    and not t.tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'worker hard-delete guard trigger missing from public.profiles';
  end if;

  select p.prosecdef,
         coalesce(array_to_string(p.proconfig, ','), '')
    into v_fn_security, v_fn_search_path
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'prevent_worker_profile_hard_delete'
    and pg_get_function_identity_arguments(p.oid) = '';

  if not coalesce(v_fn_security, false) then
    raise exception 'prevent_worker_profile_hard_delete must be SECURITY DEFINER';
  end if;

  if position('search_path=public' in replace(v_fn_search_path, ' ', '')) = 0 then
    raise exception 'prevent_worker_profile_hard_delete must pin search_path=public';
  end if;

  if has_function_privilege('authenticated', 'public.prevent_worker_profile_hard_delete()', 'EXECUTE') then
    raise exception 'authenticated must not execute delete-guard trigger function directly';
  end if;
end;
$$;

-- Behavioural check: a worker profile makes the parent profile non-deletable even
-- when deletion is initiated through a trusted database path. The transaction-local
-- maintenance override is tested separately to ensure controlled cleanup remains possible.
do $$
declare
  v_id uuid := gen_random_uuid();
  v_blocked boolean := false;
begin
  insert into auth.users(id, aud, role, email, created_at, updated_at)
  values (v_id, 'authenticated', 'authenticated', 'hard-delete-test-' || v_id || '@example.invalid', now(), now());

  insert into public.profiles(id, role, display_name)
  values (v_id, 'worker', 'Hard delete guard test');

  insert into public.worker_profiles(user_id)
  values (v_id);

  begin
    delete from public.profiles where id = v_id;
  exception when foreign_key_violation then
    v_blocked := true;
  end;

  if not v_blocked then
    raise exception 'worker profile hard deletion was not blocked';
  end if;

  perform set_config('app.allow_worker_hard_delete', 'on', true);
  delete from public.profiles where id = v_id;
  perform set_config('app.allow_worker_hard_delete', 'off', true);
  delete from auth.users where id = v_id;
end;
$$;
