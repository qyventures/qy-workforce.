-- QY Workforce V1: close direct-write gaps and harden staged identity-session lifecycle.

-- Attendance and payroll mutations must go through audited SECURITY DEFINER RPCs.
revoke insert, update, delete on public.time_events from authenticated;
revoke insert, update, delete on public.timesheets from authenticated;

-- Full margin reporting is privileged and must use get_site_margin_report().
revoke select on public.site_margin_summary from authenticated;

-- Keep at most one live identity session per worker/provider/environment.
create unique index if not exists uq_identity_provider_sessions_active
  on public.identity_provider_sessions(worker_id, provider, environment)
  where status in ('initiated','callback_received');

create or replace function public.start_identity_session(
  p_provider text default 'mock',
  p_environment text default 'mock',
  p_state_hash text default null,
  p_nonce_hash text default null,
  p_requested_scopes text[] default array['openid']::text[]
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
begin
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then
    raise exception 'worker profile required';
  end if;
  if p_provider not in ('mock','singpass_myinfo') then raise exception 'unsupported identity provider'; end if;
  if p_environment not in ('mock','staging') then raise exception 'production identity flow not enabled'; end if;
  if nullif(trim(p_state_hash),'') is null or length(trim(p_state_hash)) < 32 then raise exception 'valid state hash required'; end if;
  if nullif(trim(p_nonce_hash),'') is null or length(trim(p_nonce_hash)) < 32 then raise exception 'valid nonce hash required'; end if;
  if coalesce(array_length(p_requested_scopes,1),0) > 12 then raise exception 'too many requested scopes'; end if;
  if not exists(
    select 1 from public.worker_consents c
    where c.worker_id=auth.uid() and c.purpose='identity_verification'
      and c.granted=true and c.withdrawn_at is null
  ) then raise exception 'identity verification consent required'; end if;

  update public.identity_provider_sessions
  set status='expired'
  where worker_id=auth.uid() and provider=p_provider and environment=p_environment
    and status in ('initiated','callback_received') and expires_at<=now();

  if exists(
    select 1 from public.identity_provider_sessions
    where worker_id=auth.uid() and provider=p_provider and environment=p_environment
      and status in ('initiated','callback_received') and expires_at>now()
  ) then raise exception 'identity session already active'; end if;

  insert into public.identity_provider_sessions(
    worker_id,provider,environment,state_hash,nonce_hash,requested_scopes,expires_at
  ) values(
    auth.uid(),p_provider,p_environment,left(trim(p_state_hash),256),left(trim(p_nonce_hash),256),
    coalesce(p_requested_scopes,'{}'),now()+interval '10 minutes'
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.started','identity_provider_session',v_id,
    jsonb_build_object('provider',p_provider,'environment',p_environment));
  return v_id;
end;
$$;
revoke all on function public.start_identity_session(text,text,text,text,text[]) from public;
grant execute on function public.start_identity_session(text,text,text,text,text[]) to authenticated;

create or replace function public.mark_identity_callback_received_staging(p_session uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_environment text;
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  select environment into v_environment
  from public.identity_provider_sessions
  where id=p_session and status='initiated' and expires_at>now()
  for update;
  if v_environment is null then raise exception 'identity session unavailable'; end if;
  if v_environment not in ('mock','staging') then raise exception 'production identity callback disabled'; end if;

  update public.identity_provider_sessions set status='callback_received' where id=p_session;
  insert into public.audit_events(actor_id,action,entity_type,entity_id)
  values(auth.uid(),'identity_session.callback_received','identity_provider_session',p_session);
end;
$$;
revoke all on function public.mark_identity_callback_received_staging(uuid) from public;
grant execute on function public.mark_identity_callback_received_staging(uuid) to authenticated;

create or replace function public.fail_identity_session_staging(p_session uuid, p_error_code text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_environment text;
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if nullif(trim(p_error_code),'') is null then raise exception 'error code required'; end if;

  select environment into v_environment
  from public.identity_provider_sessions
  where id=p_session and status in ('initiated','callback_received')
  for update;
  if v_environment is null then raise exception 'identity session unavailable'; end if;
  if v_environment not in ('mock','staging') then raise exception 'production identity failure handling disabled'; end if;

  update public.identity_provider_sessions
  set status='failed', error_code=left(trim(p_error_code),100)
  where id=p_session;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'identity_session.failed','identity_provider_session',p_session,
    jsonb_build_object('error_code',left(trim(p_error_code),100)));
end;
$$;
revoke all on function public.fail_identity_session_staging(uuid,text) from public;
grant execute on function public.fail_identity_session_staging(uuid,text) to authenticated;

create or replace function public.expire_identity_sessions()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer;
begin
  if coalesce(auth.role(),'') <> 'service_role' and not public.is_ops() then raise exception 'not authorised'; end if;
  with expired as (
    update public.identity_provider_sessions
    set status='expired'
    where status in ('initiated','callback_received') and expires_at<=now()
    returning id
  )
  select count(*) into v_count from expired;

  if v_count > 0 then
    insert into public.audit_events(actor_id,action,entity_type,metadata)
    values(auth.uid(),'identity_session.expired_batch','identity_provider_session',jsonb_build_object('count',v_count));
  end if;
  return v_count;
end;
$$;
revoke all on function public.expire_identity_sessions() from public;
grant execute on function public.expire_identity_sessions() to service_role;
grant execute on function public.expire_identity_sessions() to authenticated;
