-- QY Workforce: make current residency and work-eligibility evidence part of live deployability.
-- Legacy workers without purpose-specific evidence continue to use the existing profile
-- summaries, but once evidence exists its latest outcome/expiry is authoritative.

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
      and exists (
        select 1 from public.worker_consents c
        where c.worker_id = wp.user_id
          and c.purpose = 'identity_verification'
          and c.granted = true
          and c.withdrawn_at is null
      )
      and exists (
        select 1 from public.worker_consents c
        where c.worker_id = wp.user_id
          and c.purpose = 'work_eligibility'
          and c.granted = true
          and c.withdrawn_at is null
      )
      and exists (
        select 1 from public.worker_consents c
        where c.worker_id = wp.user_id
          and c.purpose = 'location_clocking'
          and c.granted = true
          and c.withdrawn_at is null
      )
    from public.worker_profiles wp
    where wp.user_id = p_worker_id
  ), false);
$$;

revoke all on function public.worker_has_deployment_prerequisites(uuid) from public;

comment on function public.worker_has_deployment_prerequisites(uuid) is
'Authoritative live readiness predicate. Identity, current residency, and current work eligibility are evaluated separately alongside consent, role, vetting and training.';
