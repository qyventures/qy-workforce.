-- Structural regression checks for latest-decision operational consent and matching.

do $$
declare v_def text;
begin
  if not (select relrowsecurity from pg_class where oid='public.worker_consents'::regclass) then
    raise exception 'worker_consents must have RLS enabled';
  end if;
  if has_table_privilege('authenticated','public.worker_consents','INSERT,UPDATE,DELETE') then
    raise exception 'authenticated direct worker consent mutation must be denied';
  end if;
  if has_function_privilege('anon','public.set_worker_operational_consent(text,boolean,text)','EXECUTE') then
    raise exception 'anon must not execute operational consent RPC';
  end if;
  if not has_function_privilege('authenticated','public.set_worker_operational_consent(text,boolean,text)','EXECUTE') then
    raise exception 'authenticated operational consent RPC grant missing';
  end if;
  select pg_get_functiondef('public.worker_has_active_consent(uuid,text)'::regprocedure) into v_def;
  if position('order by c.recorded_at desc, c.decision_sequence desc' in lower(v_def))=0
     or position('limit 1' in lower(v_def))=0 then
    raise exception 'consent predicate must use the latest decision';
  end if;
  if position('worker_has_active_consent' in pg_get_functiondef('public.worker_has_deployment_prerequisites(uuid)'::regprocedure))=0 then
    raise exception 'deployment prerequisites must use authoritative consent state';
  end if;
  if position('worker_has_active_consent' in pg_get_functiondef('public.start_identity_session(text,text,text,text,text[])'::regprocedure))=0 then
    raise exception 'identity session start must use authoritative consent state';
  end if;
  select pg_get_functiondef('public.get_available_shifts()'::regprocedure) into v_def;
  if position('worker_is_deployable(auth.uid())' in lower(v_def))=0 then
    raise exception 'shift feed must retain the final Ops deployability gate';
  end if;
end;
$$;
