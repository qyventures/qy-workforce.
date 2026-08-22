-- Regression checks for 0028_audit_metadata_minimisation.sql.
-- Intended for non-production test/staging databases only.

begin;

-- Harmless audit metadata remains permitted by the detector.
do $$
begin
  if public.audit_metadata_contains_sensitive_keys(
    '{"decision":"approved","worker_id":"00000000-0000-0000-0000-000000000001","provider_subject_hash":"sha256:abc"}'::jsonb
  ) then
    raise exception 'safe audit metadata was incorrectly rejected';
  end if;
end;
$$;

-- Sensitive keys must be detected even when nested or inside arrays.
do $$
begin
  if not public.audit_metadata_contains_sensitive_keys(
    '{"verification":{"raw_payload":{"nric":"S0000000A"}}}'::jsonb
  ) then
    raise exception 'nested sensitive audit metadata was not detected';
  end if;

  if not public.audit_metadata_contains_sensitive_keys(
    '{"items":[{"result":"ok"},{"access_token":"secret"}]}'::jsonb
  ) then
    raise exception 'array-contained sensitive audit metadata was not detected';
  end if;
end;
$$;

-- Confirm the trigger is installed on audit_events.
do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'audit_events'
      and t.tgname = 'audit_metadata_minimisation_guard'
      and not t.tgisinternal
  ) then
    raise exception 'audit metadata minimisation trigger is missing';
  end if;
end;
$$;

-- The database trigger must reject prohibited fields, not only the helper function.
do $$
begin
  begin
    insert into public.audit_events(action, entity_type, metadata)
    values ('test.sensitive_metadata', 'test', '{"myinfo_payload":{"name":"Example"}}'::jsonb);
    raise exception 'sensitive audit insert unexpectedly succeeded';
  exception
    when sqlstate '22023' then
      null;
  end;
end;
$$;

rollback;
