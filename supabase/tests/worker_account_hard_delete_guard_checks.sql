-- Security regression checks for worker hard-delete protection.
-- These assertions are schema-safe and do not manufacture auth.users rows.

do $$
declare
  v_trigger_count integer;
  v_fn_security boolean;
  v_fn_search_path text;
  v_fn_source text;
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

  if has_table_privilege('anon', 'public.worker_profiles', 'DELETE') then
    raise exception 'anon must not have DELETE on public.worker_profiles';
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
         coalesce(array_to_string(p.proconfig, ','), ''),
         pg_get_functiondef(p.oid)
    into v_fn_security, v_fn_search_path, v_fn_source
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

  if has_function_privilege('anon', 'public.prevent_worker_profile_hard_delete()', 'EXECUTE') then
    raise exception 'anon must not execute delete-guard trigger function directly';
  end if;

  if position('allow_worker_hard_delete' in coalesce(v_fn_source, '')) = 0
     or position('worker_profiles' in coalesce(v_fn_source, '')) = 0
     or position('privacy erasure and retention workflow' in coalesce(v_fn_source, '')) = 0 then
    raise exception 'delete guard must require explicit maintenance override and protect worker rows';
  end if;
end;
$$;
