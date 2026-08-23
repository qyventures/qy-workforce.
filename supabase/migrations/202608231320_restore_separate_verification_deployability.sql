-- QY Workforce: restore purpose-specific residency/work-eligibility checks in deployability.
-- A later consent-version migration re-issued this predicate using only denormalised
-- worker_profile summary columns. Keep current-version consent while restoring the
-- expiry-aware evidence helpers introduced by verification separation.

create or replace function public.worker_has_deployment_prerequisites(p_worker_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select
      wp.identity_verified
      and public.worker_has_current_residency(wp.user_id)
      and public.worker_has_current_work_eligibility(wp.user_id)
      and wp.status not in ('suspended','rejected')
      and exists (
        select 1
        from public.worker_roles wr
        join public.roles r on r.id = wr.role_id
        where wr.worker_id = wp.user_id
          and wr.approved = true
          and r.active = true
      )
      and not exists (
        select 1
        from public.worker_vetting wv
        where wv.worker_id = wp.user_id
          and wv.status in ('pending','failed','manual_review')
      )
      and not exists (
        select 1
        from public.training_modules tm
        where tm.active = true
          and (
            tm.role_id is null
            or exists (
              select 1
              from public.worker_roles wr
              where wr.worker_id = wp.user_id
                and wr.role_id = tm.role_id
                and wr.approved = true
            )
          )
          and not exists (
            select 1
            from public.worker_training wt
            where wt.worker_id = wp.user_id
              and wt.module_id = tm.id
              and wt.status = 'passed'
              and (wt.expires_at is null or wt.expires_at > now())
          )
      )
      and public.worker_has_current_consent(wp.user_id,'identity_verification')
      and public.worker_has_current_consent(wp.user_id,'work_eligibility')
      and public.worker_has_current_consent(wp.user_id,'location_clocking')
    from public.worker_profiles wp
    where wp.user_id = p_worker_id
  ), false);
$$;

revoke all on function public.worker_has_deployment_prerequisites(uuid) from public;

comment on function public.worker_has_deployment_prerequisites(uuid) is
'Authoritative live readiness predicate. Identity, current residency evidence, current work-eligibility evidence, current-version consent, role, vetting and training are evaluated independently.';
