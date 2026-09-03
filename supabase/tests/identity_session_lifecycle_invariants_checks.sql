-- Structural checks for coherent staged identity-session terminal evidence.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.identity_provider_sessions'::regclass
      and conname='identity_provider_sessions_terminal_evidence_consistency'
      and not convalidated
  ) then
    raise exception 'identity session terminal evidence constraint must be a NOT VALID forward-write constraint';
  end if;
end $$;

do $$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid='public.identity_provider_sessions'::regclass
    and conname='identity_provider_sessions_terminal_evidence_consistency';

  if v_def is null
     or position('status = ''completed''' in lower(v_def)) = 0
     or position('status = ''failed''' in lower(v_def)) = 0
     or position('status = ''expired''' in lower(v_def)) = 0
     or position('provider_subject_hash is null' in lower(v_def)) = 0
     or position('error_code is null' in lower(v_def)) = 0
     or position('error_code is not null' in lower(v_def)) = 0
     or position('error_code ~' in lower(v_def)) = 0 then
    raise exception 'identity session lifecycle states must have mutually exclusive evidence';
  end if;
end $$;

do $$
declare v_def text;
begin
  select pg_get_functiondef('public.fail_identity_session_staging(uuid,text)'::regprocedure)
    into v_def;
  if position('invalid redacted error code' in lower(v_def)) = 0
     or position('v_error_code' in lower(v_def)) = 0 then
    raise exception 'identity failure RPC must accept only bounded redacted error codes';
  end if;
end $$;
