begin;

-- The authenticated API role must not have direct DELETE privilege on shifts.
do $$
begin
  if has_table_privilege('authenticated', 'public.shifts', 'DELETE') then
    raise exception 'authenticated unexpectedly has DELETE privilege on public.shifts';
  end if;
  if has_table_privilege('anon', 'public.shifts', 'DELETE') then
    raise exception 'anon unexpectedly has DELETE privilege on public.shifts';
  end if;
end
$$;

-- A BEFORE DELETE guard must remain installed so later grant/RLS changes cannot
-- silently reintroduce destructive authenticated deletion.
do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'shifts'
      and t.tgname = 'prevent_authenticated_shift_delete'
      and not t.tgisinternal
  ) then
    raise exception 'shift deletion integrity trigger missing';
  end if;
end
$$;

-- The trigger function must run with a pinned search_path and must not be
-- executable by PUBLIC.
do $$
declare
  v_security_definer boolean;
  v_config text[];
begin
  select p.prosecdef, p.proconfig
    into v_security_definer, v_config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'prevent_authenticated_shift_delete'
    and pg_get_function_identity_arguments(p.oid) = '';

  if not coalesce(v_security_definer, false) then
    raise exception 'prevent_authenticated_shift_delete must be SECURITY DEFINER';
  end if;

  if v_config is null or not exists (
    select 1 from unnest(v_config) cfg
    where cfg like 'search_path=%'
  ) then
    raise exception 'prevent_authenticated_shift_delete must pin search_path';
  end if;

  if has_function_privilege('public', 'public.prevent_authenticated_shift_delete()', 'EXECUTE') then
    raise exception 'PUBLIC must not execute prevent_authenticated_shift_delete directly';
  end if;
end
$$;

rollback;
