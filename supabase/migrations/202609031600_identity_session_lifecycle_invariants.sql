-- QY Workforce: keep mock/staging identity-session terminal evidence coherent.
-- NOT VALID preserves legacy staging rows while enforcing every new write/update.

alter table public.identity_provider_sessions
  drop constraint if exists identity_provider_sessions_terminal_evidence_consistency;

alter table public.identity_provider_sessions
  add constraint identity_provider_sessions_terminal_evidence_consistency
  check (
    (status = 'completed'
      and completed_at is not null
      and provider_subject_hash is not null
      and error_code is null)
    or (status = 'failed'
      and completed_at is null
      and provider_subject_hash is null
      and error_code is not null
      and error_code ~ '^[a-z0-9_.:-]{1,100}$')
    or (status = 'expired'
      and completed_at is null
      and provider_subject_hash is null
      and error_code is null)
    or (status in ('initiated','callback_received')
      and completed_at is null
      and provider_subject_hash is null
      and error_code is null)
  ) not valid;

comment on constraint identity_provider_sessions_terminal_evidence_consistency
  on public.identity_provider_sessions is
  'A session may carry only evidence appropriate to its lifecycle state; raw provider payloads and tokens remain outside this table.';

-- Failure codes are operational categories, not a place to persist provider
-- messages, tokens or personal data. Normalize and bound the RPC input before
-- it reaches the session row or audit metadata.
create or replace function public.fail_identity_session_staging(
  p_session uuid,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_environment text;
  v_error_code text := lower(nullif(trim(p_error_code), ''));
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if v_error_code is null or v_error_code !~ '^[a-z0-9_.:-]{1,100}$' then
    raise exception 'invalid redacted error code';
  end if;

  select environment into v_environment
  from public.identity_provider_sessions
  where id = p_session and status in ('initiated','callback_received')
  for update;
  if v_environment is null then raise exception 'identity session unavailable'; end if;
  if v_environment not in ('mock','staging') then
    raise exception 'production identity failure handling disabled';
  end if;

  update public.identity_provider_sessions
     set status = 'failed', error_code = v_error_code
   where id = p_session;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.failed','identity_provider_session',p_session,
         jsonb_build_object('error_code',v_error_code));
end;
$$;

revoke all on function public.fail_identity_session_staging(uuid,text) from public;
grant execute on function public.fail_identity_session_staging(uuid,text) to authenticated;
