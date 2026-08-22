-- QY Workforce: retention for separated residency and work-eligibility evidence.
-- Identity, residency and work eligibility remain independent lifecycles. This migration
-- minimises purpose-specific evidence hashes after the configured retention window while
-- preserving the decision, timestamps and validity needed for audit/dispute history.

insert into public.data_retention_policies(data_class, retention_days, rationale)
select 'residency_verification_evidence',
       coalesce((select retention_days from public.data_retention_policies where data_class='identity_verifications'),730),
       'Minimise residency evidence metadata after the verification retention window; preserve decision history only'
where not exists (
  select 1 from public.data_retention_policies where data_class='residency_verification_evidence'
);

insert into public.data_retention_policies(data_class, retention_days, rationale)
select 'work_eligibility_evidence',
       coalesce((select retention_days from public.data_retention_policies where data_class='identity_verifications'),730),
       'Minimise work-eligibility evidence metadata after the verification retention window; preserve decision history only'
where not exists (
  select 1 from public.data_retention_policies where data_class='work_eligibility_evidence'
);

create or replace function public.run_verification_evidence_retention(
  p_execute boolean default false,
  p_batch_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role := public.current_app_role();
  v_is_service boolean := coalesce(auth.role() = 'service_role', false);
  v_limit integer := greatest(1, least(coalesce(p_batch_limit,500),5000));
  v_residency_days integer;
  v_work_days integer;
  v_residency_count integer := 0;
  v_work_count integer := 0;
  v_run uuid;
  v_result jsonb;
begin
  if p_execute then
    if v_role <> 'admin' and not v_is_service then
      raise exception 'admin or service role required';
    end if;
  else
    if v_role not in ('admin','auditor') and not v_is_service then
      raise exception 'admin, auditor or service role required';
    end if;
  end if;

  select retention_days into v_residency_days
  from public.data_retention_policies
  where data_class='residency_verification_evidence';

  select retention_days into v_work_days
  from public.data_retention_policies
  where data_class='work_eligibility_evidence';

  if v_residency_days is null or v_work_days is null then
    raise exception 'verification evidence retention policy missing';
  end if;

  if not p_execute then
    select least(count(*)::integer,v_limit) into v_residency_count
    from public.residency_verifications rv
    where rv.checked_at < now() - make_interval(days=>v_residency_days)
      and rv.evidence_hash is not null
      and not exists (
        select 1 from public.privacy_requests pr
        where pr.worker_id=rv.worker_id and pr.retention_hold=true
      );

    select least(count(*)::integer,v_limit) into v_work_count
    from public.work_eligibility_checks we
    where we.checked_at < now() - make_interval(days=>v_work_days)
      and we.evidence_hash is not null
      and not exists (
        select 1 from public.privacy_requests pr
        where pr.worker_id=we.worker_id and pr.retention_hold=true
      );
  else
    update public.residency_verifications rv
       set evidence_hash=null
     where rv.id in (
       select rv2.id
       from public.residency_verifications rv2
       where rv2.checked_at < now() - make_interval(days=>v_residency_days)
         and rv2.evidence_hash is not null
         and not exists (
           select 1 from public.privacy_requests pr
           where pr.worker_id=rv2.worker_id and pr.retention_hold=true
         )
       order by rv2.checked_at asc, rv2.id asc
       limit v_limit
     );
    get diagnostics v_residency_count = row_count;

    update public.work_eligibility_checks we
       set evidence_hash=null
     where we.id in (
       select we2.id
       from public.work_eligibility_checks we2
       where we2.checked_at < now() - make_interval(days=>v_work_days)
         and we2.evidence_hash is not null
         and not exists (
           select 1 from public.privacy_requests pr
           where pr.worker_id=we2.worker_id and pr.retention_hold=true
         )
       order by we2.checked_at asc, we2.id asc
       limit v_limit
     );
    get diagnostics v_work_count = row_count;
  end if;

  v_result := jsonb_build_object(
    'execute',p_execute,
    'batch_limit',v_limit,
    'residency_evidence_minimised',v_residency_count,
    'work_eligibility_evidence_minimised',v_work_count,
    'decision_history_preserved',true,
    'retention_holds_honoured',true
  );

  insert into public.retention_runs(requested_by,execute_mode,batch_limit,policy_snapshot,result_counts)
  values(
    auth.uid(),p_execute,v_limit,
    jsonb_build_object(
      'residency_verification_evidence_days',v_residency_days,
      'work_eligibility_evidence_days',v_work_days
    ),
    v_result
  ) returning id into v_run;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    case when p_execute then 'retention.verification_evidence_executed' else 'retention.verification_evidence_previewed' end,
    'retention_run',v_run,v_result
  );

  return v_result || jsonb_build_object('run_id',v_run);
end;
$$;

revoke all on function public.run_verification_evidence_retention(boolean,integer) from public;
grant execute on function public.run_verification_evidence_retention(boolean,integer) to authenticated, service_role;

comment on function public.run_verification_evidence_retention(boolean,integer) is
'Audited, batch-capped minimisation of separated residency/work-eligibility evidence hashes. Preview is Admin/Auditor/service-role; execution is Admin/service-role and honours worker retention holds.';
