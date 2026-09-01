-- Make the mock/staging identity-session state machine fail closed.  Session
-- transport hashes remain confidential and identity, residency and work
-- eligibility continue to be decided at separate boundaries.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.identity_provider_sessions'::regclass
      and conname = 'identity_provider_sessions_lifecycle_data_check'
  ) then
    alter table public.identity_provider_sessions
      add constraint identity_provider_sessions_lifecycle_data_check
      check (
        expires_at > created_at
        and (
          (status in ('initiated', 'callback_received')
            and provider_subject_hash is null and error_code is null and completed_at is null)
          or
          (status = 'completed'
            and provider_subject_hash is not null
            and char_length(provider_subject_hash) between 32 and 256
            and provider_subject_hash ~ '^[0-9a-f]+$'
            and error_code is null
            and completed_at is not null
            and completed_at <= expires_at)
          or
          (status = 'failed'
            and provider_subject_hash is null
            and completed_at is null
            and char_length(error_code) between 1 and 100)
          or
          (status = 'expired'
            and provider_subject_hash is null and error_code is null and completed_at is null)
        )
      ) not valid;
  end if;
end;
$$;

create or replace function public.guard_identity_provider_session_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.worker_id is distinct from old.worker_id
     or new.provider is distinct from old.provider
     or new.environment is distinct from old.environment
     or new.state_hash is distinct from old.state_hash
     or new.nonce_hash is distinct from old.nonce_hash
     or new.requested_scopes is distinct from old.requested_scopes
     or new.expires_at is distinct from old.expires_at
     or new.created_at is distinct from old.created_at then
    raise exception 'identity session transport fields are immutable';
  end if;

  if old.status = 'initiated' and new.status in ('callback_received', 'failed', 'expired') then
    return new;
  end if;
  if old.status = 'callback_received' and new.status in ('completed', 'failed', 'expired') then
    return new;
  end if;

  raise exception 'invalid identity session state transition';
end;
$$;
revoke all on function public.guard_identity_provider_session_transition() from public, anon, authenticated;

drop trigger if exists identity_provider_sessions_transition_guard on public.identity_provider_sessions;
create trigger identity_provider_sessions_transition_guard
before update on public.identity_provider_sessions
for each row execute function public.guard_identity_provider_session_transition();

comment on function public.guard_identity_provider_session_transition() is
  'Internal state-machine guard for mock/staging identity sessions. Transport fields cannot change after creation and terminal sessions cannot be reopened.';

