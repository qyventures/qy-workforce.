-- Security regression checks for append-only audit history.
-- Run after applying all migrations in an isolated test database.

begin;

-- The append-only trigger must exist.
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

-- The guard has no elevated privilege and pins its search path.
do $$
declare
  v_def text;
  v_config text[];
  v_secdef boolean;
begin
  select pg_get_functiondef(p.oid), p.proconfig, p.prosecdef
    into v_def, v_config, v_secdef
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'reject_audit_event_mutation'
    and pg_get_function_identity_arguments(p.oid) = '';

  if v_def is null then
    raise exception 'audit mutation guard missing';
  end if;
  if v_secdef then
    raise exception 'audit mutation guard must not use SECURITY DEFINER';
  end if;
  if v_config is null or not ('search_path=pg_catalog, public' = any(v_config)) then
    raise exception 'audit mutation guard must pin search_path';
  end if;
end $$;

-- Authenticated and anonymous roles must not retain mutation privileges.
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

-- Even a privileged migration/test context must not rewrite or delete history.
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
