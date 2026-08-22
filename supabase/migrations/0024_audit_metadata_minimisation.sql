-- Prevent highly sensitive identity/authentication payloads from being copied into audit JSON.
-- Audit events should reference entity IDs and decision/result metadata, not raw evidence.

create or replace function public.audit_metadata_contains_sensitive_keys(p_value jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = pg_catalog, public
as $$
declare
  v_key text;
  v_child jsonb;
begin
  if jsonb_typeof(p_value) = 'object' then
    for v_key, v_child in select key, value from jsonb_each(p_value)
    loop
      if lower(v_key) = any (array[
        'nric',
        'fin',
        'passport',
        'passport_number',
        'national_id',
        'identity_number',
        'document_number',
        'work_pass_number',
        'raw_payload',
        'raw_response',
        'singpass_payload',
        'myinfo_payload',
        'verified_attributes',
        'access_token',
        'refresh_token',
        'id_token',
        'authorization'
      ]) then
        return true;
      end if;

      if jsonb_typeof(v_child) in ('object', 'array')
         and public.audit_metadata_contains_sensitive_keys(v_child) then
        return true;
      end if;
    end loop;
  elsif jsonb_typeof(p_value) = 'array' then
    for v_child in select value from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_child) in ('object', 'array')
         and public.audit_metadata_contains_sensitive_keys(v_child) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

-- The helper is an implementation detail of the trigger. Authenticated clients do not
-- need direct EXECUTE permission; keeping it owner-only reduces callable surface area.
revoke all on function public.audit_metadata_contains_sensitive_keys(jsonb) from public;
revoke all on function public.audit_metadata_contains_sensitive_keys(jsonb) from anon, authenticated;

create or replace function public.enforce_audit_metadata_minimisation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if public.audit_metadata_contains_sensitive_keys(coalesce(new.metadata, '{}'::jsonb)) then
    raise exception 'audit metadata contains prohibited sensitive fields'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_audit_metadata_minimisation() from public;
revoke all on function public.enforce_audit_metadata_minimisation() from anon, authenticated;

-- Fail immediately in the same statement that attempts to copy sensitive evidence.
drop trigger if exists audit_metadata_minimisation_guard on public.audit_events;
create trigger audit_metadata_minimisation_guard
before insert or update of metadata on public.audit_events
for each row
execute function public.enforce_audit_metadata_minimisation();

comment on function public.audit_metadata_contains_sensitive_keys(jsonb) is
  'Recursively detects prohibited raw identity/authentication fields in audit metadata. Hashed references and entity IDs remain allowed.';

comment on trigger audit_metadata_minimisation_guard on public.audit_events is
  'Blocks raw/highly sensitive identity and authentication evidence from being persisted in audit_events.metadata.';
