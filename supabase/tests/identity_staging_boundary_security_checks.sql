-- QY Workforce mock/staging identity-session security invariants.
-- Intended for staging/CI after all migrations are applied.

do $$
declare
  v_def text;
  v_rls boolean;
begin
  select relrowsecurity into v_rls
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='identity_provider_sessions';
  if not coalesce(v_rls,false) then raise exception 'identity sessions must have RLS enabled'; end if;

  if has_table_privilege('authenticated','public.identity_provider_sessions','INSERT')
     or has_table_privilege('authenticated','public.identity_provider_sessions','UPDATE')
     or has_table_privilege('authenticated','public.identity_provider_sessions','DELETE')
     or has_table_privilege('authenticated','public.identity_verifications','INSERT')
     or has_table_privilege('authenticated','public.identity_verifications','UPDATE')
     or has_table_privilege('authenticated','public.identity_verifications','DELETE') then
    raise exception 'identity session and verification writes must be RPC/service-only';
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='start_identity_session'
    and pg_get_function_identity_arguments(p.oid)='p_provider text, p_environment text, p_state_hash text, p_nonce_hash text, p_requested_scopes text[]';
  if v_def is null or position('only the openid scope is permitted' in v_def)=0
     or position('identity verification consent required' in v_def)=0
     or position('identity session already active' in v_def)=0 then
    raise exception 'identity-session start must be consent-bound, scope-minimised and single-active';
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='complete_identity_verification_staging';
  if v_def is null or position('status=''callback_received''' in v_def)=0
     or position('valid provider subject hash required' in v_def)=0
     or position('residency category requires verified residency' in v_def)=0 then
    raise exception 'identity completion must require callback state, a correlation hash and verified residency before recording residency category';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.identity_provider_sessions'::regclass
      and conname='identity_provider_sessions_completion_check'
  ) then raise exception 'identity sessions must enforce terminal completion evidence'; end if;
end;
$$;
