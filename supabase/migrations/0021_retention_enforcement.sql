-- QY Workforce: executable, audited retention enforcement.
-- This job deliberately minimises/deletes only data classes whose lifecycle is already
-- defined and operationally safe. Payroll, timesheets, privacy-request evidence and
-- audit-event history remain manual/legal-review classes in V1.

insert into public.data_retention_policies(data_class, retention_days, rationale) values
  ('identity_sessions', 30, 'Ephemeral mock/staging identity correlation data; completed/failed/expired sessions should not persist long-term')
on conflict (data_class) do nothing;

create table if not exists public.retention_runs (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid references public.profiles(id),
  execute_mode boolean not null default false,
  batch_limit integer not null check (batch_limit between 1 and 5000),
  policy_snapshot jsonb not null default '{}'::jsonb,
  result_counts jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.retention_runs enable row level security;

create policy "retention admins audit runs" on public.retention_runs
for select using (public.current_app_role() in ('admin','auditor'));

revoke insert, update, delete on public.retention_runs from authenticated;

create or replace function public.run_retention_maintenance(
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
  v_public_days integer;
  v_location_days integer;
  v_identity_days integer;
  v_session_days integer;
  v_employer_count integer := 0;
  v_worker_lead_count integer := 0;
  v_location_count integer := 0;
  v_identity_count integer := 0;
  v_session_count integer := 0;
  v_run uuid;
  v_result jsonb;
begin
  -- Auditors can preview. Only Admin or service-role scheduling can execute destructive/minimising work.
  if p_execute then
    if v_role <> 'admin' and not v_is_service then raise exception 'admin or service role required'; end if;
  else
    if v_role not in ('admin','auditor') and not v_is_service then raise exception 'admin, auditor or service role required'; end if;
  end if;

  select retention_days into v_public_days from public.data_retention_policies where data_class='public_leads';
  select retention_days into v_location_days from public.data_retention_policies where data_class='location_events';
  select retention_days into v_identity_days from public.data_retention_policies where data_class='identity_verifications';
  select retention_days into v_session_days from public.data_retention_policies where data_class='identity_sessions';

  if v_public_days is null or v_location_days is null or v_identity_days is null or v_session_days is null then
    raise exception 'required retention policy missing';
  end if;

  if not p_execute then
    select least(count(*)::integer,v_limit) into v_employer_count
      from public.employer_leads where created_at < now() - make_interval(days=>v_public_days);
    select least(count(*)::integer,v_limit) into v_worker_lead_count
      from public.worker_interest_leads where created_at < now() - make_interval(days=>v_public_days);

    select least(count(*)::integer,v_limit) into v_location_count
    from public.time_events te
    join public.shift_assignments sa on sa.id=te.assignment_id
    where te.occurred_at < now() - make_interval(days=>v_location_days)
      and (te.latitude is not null or te.longitude is not null or te.accuracy_m is not null or te.device_fingerprint_hash is not null)
      and not exists (
        select 1 from public.privacy_requests pr
        where pr.worker_id=sa.worker_id and pr.retention_hold=true
      );

    select least(count(*)::integer,v_limit) into v_identity_count
    from public.identity_verifications iv
    where iv.created_at < now() - make_interval(days=>v_identity_days)
      and (iv.provider_subject_hash is not null or iv.verified_attributes <> '{}'::jsonb)
      and not exists (
        select 1 from public.privacy_requests pr
        where pr.worker_id=iv.worker_id and pr.retention_hold=true
      );

    select least(count(*)::integer,v_limit) into v_session_count
    from public.identity_provider_sessions ips
    where ips.created_at < now() - make_interval(days=>v_session_days)
      and ips.status in ('completed','failed','expired')
      and not exists (
        select 1 from public.privacy_requests pr
        where pr.worker_id=ips.worker_id and pr.retention_hold=true
      );
  else
    delete from public.employer_leads
    where id in (
      select id from public.employer_leads
      where created_at < now() - make_interval(days=>v_public_days)
      order by created_at asc limit v_limit
    );
    get diagnostics v_employer_count = row_count;

    delete from public.worker_interest_leads
    where id in (
      select id from public.worker_interest_leads
      where created_at < now() - make_interval(days=>v_public_days)
      order by created_at asc limit v_limit
    );
    get diagnostics v_worker_lead_count = row_count;

    -- Retain attendance chronology/geofence outcome for payroll/dispute evidence, but remove
    -- precise coordinates, accuracy and device correlation after the location retention window.
    update public.time_events te
       set latitude=null, longitude=null, accuracy_m=null, device_fingerprint_hash=null
     where te.id in (
       select te2.id
       from public.time_events te2
       join public.shift_assignments sa on sa.id=te2.assignment_id
       where te2.occurred_at < now() - make_interval(days=>v_location_days)
         and (te2.latitude is not null or te2.longitude is not null or te2.accuracy_m is not null or te2.device_fingerprint_hash is not null)
         and not exists (
           select 1 from public.privacy_requests pr
           where pr.worker_id=sa.worker_id and pr.retention_hold=true
         )
       order by te2.occurred_at asc limit v_limit
     );
    get diagnostics v_location_count = row_count;

    -- Preserve only the normalized historical verification outcome. Current readiness remains
    -- on worker_profiles; raw provider correlation and attribute metadata are no longer needed.
    update public.identity_verifications iv
       set provider_subject_hash=null,
           verified_attributes=jsonb_strip_nulls(jsonb_build_object(
             'identity_verified', iv.verified_attributes->'identity_verified',
             'residency_verified', iv.verified_attributes->'residency_verified',
             'work_eligibility', iv.verified_attributes->'work_eligibility'
           ))
     where iv.id in (
       select iv2.id
       from public.identity_verifications iv2
       where iv2.created_at < now() - make_interval(days=>v_identity_days)
         and (iv2.provider_subject_hash is not null or iv2.verified_attributes <> '{}'::jsonb)
         and not exists (
           select 1 from public.privacy_requests pr
           where pr.worker_id=iv2.worker_id and pr.retention_hold=true
         )
       order by iv2.created_at asc limit v_limit
     );
    get diagnostics v_identity_count = row_count;

    delete from public.identity_provider_sessions ips
    where ips.id in (
      select ips2.id
      from public.identity_provider_sessions ips2
      where ips2.created_at < now() - make_interval(days=>v_session_days)
        and ips2.status in ('completed','failed','expired')
        and not exists (
          select 1 from public.privacy_requests pr
          where pr.worker_id=ips2.worker_id and pr.retention_hold=true
        )
      order by ips2.created_at asc limit v_limit
    );
    get diagnostics v_session_count = row_count;
  end if;

  v_result := jsonb_build_object(
    'execute',p_execute,
    'batch_limit',v_limit,
    'employer_leads',v_employer_count,
    'worker_interest_leads',v_worker_lead_count,
    'location_events_minimised',v_location_count,
    'identity_verifications_minimised',v_identity_count,
    'identity_sessions_deleted',v_session_count,
    'manual_review_classes',jsonb_build_array('audit_events','privacy_requests','payroll_and_timesheets')
  );

  insert into public.retention_runs(requested_by,execute_mode,batch_limit,policy_snapshot,result_counts)
  values(
    auth.uid(),p_execute,v_limit,
    jsonb_build_object(
      'public_leads_days',v_public_days,
      'location_events_days',v_location_days,
      'identity_verifications_days',v_identity_days,
      'identity_sessions_days',v_session_days
    ),
    v_result
  ) returning id into v_run;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),
         case when p_execute then 'retention.maintenance_executed' else 'retention.maintenance_previewed' end,
         'retention_run',v_run,
         v_result);

  return v_result || jsonb_build_object('run_id',v_run);
end;
$$;

revoke all on function public.run_retention_maintenance(boolean,integer) from public;
grant execute on function public.run_retention_maintenance(boolean,integer) to authenticated, service_role;

comment on function public.run_retention_maintenance(boolean,integer) is
'Audited, batch-capped retention preview/execution. Execution is Admin/service-role only and honours worker retention holds.';
