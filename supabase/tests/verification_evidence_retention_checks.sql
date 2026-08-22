-- Security/retention assertions for purpose-specific verification evidence.
-- Intended for a migrated test database.

do $$
declare
  v_def text;
  v_secdef boolean;
  v_public_exec boolean;
  v_auth_exec boolean;
  v_service_exec boolean;
begin
  select p.prosecdef,
         pg_get_functiondef(p.oid)
    into v_secdef,v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='run_verification_evidence_retention'
    and pg_get_function_identity_arguments(p.oid)='p_execute boolean, p_batch_limit integer';

  if v_def is null then raise exception 'run_verification_evidence_retention missing'; end if;
  if not v_secdef then raise exception 'verification evidence retention RPC must be SECURITY DEFINER'; end if;
  if position('SET search_path TO public' in v_def)=0 and position('SET search_path = public' in v_def)=0 then
    raise exception 'verification evidence retention RPC must pin search_path';
  end if;
  if position('retention_hold=true' in replace(v_def,' ',''))=0 then
    raise exception 'verification evidence retention must honour privacy retention holds';
  end if;
  if position('evidence_hash = NULL' in upper(v_def))=0 and position('evidence_hash=null' in lower(v_def))=0 then
    raise exception 'verification evidence retention must minimise evidence hashes';
  end if;
  if position('residency_verifications' in v_def)=0 or position('work_eligibility_checks' in v_def)=0 then
    raise exception 'identity, residency and work eligibility retention must stay purpose-specific';
  end if;

  select has_function_privilege('public','public.run_verification_evidence_retention(boolean,integer)','EXECUTE') into v_public_exec;
  select has_function_privilege('authenticated','public.run_verification_evidence_retention(boolean,integer)','EXECUTE') into v_auth_exec;
  select has_function_privilege('service_role','public.run_verification_evidence_retention(boolean,integer)','EXECUTE') into v_service_exec;

  if v_public_exec then raise exception 'public must not execute verification evidence retention'; end if;
  if not v_auth_exec then raise exception 'authenticated role needs RPC access for role-checked Admin/Auditor preview'; end if;
  if not v_service_exec then raise exception 'service_role needs retention execution access'; end if;

  if not exists(select 1 from public.data_retention_policies where data_class='residency_verification_evidence') then
    raise exception 'residency evidence retention policy missing';
  end if;
  if not exists(select 1 from public.data_retention_policies where data_class='work_eligibility_evidence') then
    raise exception 'work eligibility evidence retention policy missing';
  end if;
end $$;
