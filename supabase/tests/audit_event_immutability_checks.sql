-- Security regression checks for append-only audit history.
-- Run after applying all migrations in an isolated test database.

begin;

-- The append-only trigger must exist and guard both UPDATE and DELETE paths.
do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'audit_events'
      and t.tgname = 'audit_events_append_only'
      and not t.tgisinternal
  ) then
    raise exception 'audit_events append-only trigger missing';
  end if;
end $$;

-- The guard function must be SECURITY DEFINER with a fixed search_path.
do $$
declare
  v_def text;
  v_config text[];
begin
  select pg_get_functiondef(p.oid), p.proconfig
    into v_def, v_config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'reject_audit_event_mutation'
    and pg_get_function_identity_arguments(p.oid) = '';

  if v_def is null or position('SECURITY DEFINER' in upper(v_def)) = 0 then
    raise exception 'audit mutation guard must be SECURITY DEFINER';
  end if;

  if v_config is null or not ('search_path=public' = any(v_config)) then
    raise exception 'audit mutation guard must pin search_path=public';
  end if;
end $$;

-- Authenticated and anon roles must not have direct UPDATE/DELETE/TRUNCATE privileges.
do $$
begin
  if has_table_privilege('authenticated','public.audit_events','UPDATE')
     or has_table_privilege('authenticated','public.audit_events','DELETE')
     or has_table_privilege('authenticated','public.audit_events','TRUNCATE') then
    raise exception 'authenticated retains audit mutation privilege';
  end if;

  if has_table_privilege('anon','public.audit_events','UPDATE')
     or has_table_privilege('anon','public.audit_events','DELETE')
     or has_table_privilege('anon','public.audit_events','TRUNCATE') then
    raise exception 'anon retains audit mutation privilege';
  end if;
end $$;

-- Even a privileged SQL context cannot rewrite or delete an existing event.
do $$
declare
  v_id uuid;
begin
  insert into public.audit_events(action,entity_type,metadata)
  values ('test.append_only','security_test','{}'::jsonb)
  returning id into v_id;

  begin
    update public.audit_events set action='test.tampered' where id=v_id;
    raise exception 'audit UPDATE unexpectedly succeeded';
  exception when raise_exception then
    if sqlerrm <> 'audit events are append-only' then raise; end if;
  end;

  begin
    delete from public.audit_events where id=v_id;
    raise exception 'audit DELETE unexpectedly succeeded';
  exception when raise_exception then
    if sqlerrm <> 'audit events are append-only' then raise; end if;
  end;
end $$;

rollback;
