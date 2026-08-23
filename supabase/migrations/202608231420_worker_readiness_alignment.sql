-- QY Workforce: align the worker-facing readiness summary with the authoritative
-- live deployability predicate and the separate, expiry-aware residency/work-
-- eligibility evidence helpers.
--
-- This preserves the existing RPC signature for mobile compatibility while
-- preventing stale denormalised profile flags or historical consent rows from
-- making the readiness screen disagree with secure shift acceptance.

create or replace function public.get_worker_readiness()
returns table (
  worker_status public.worker_status,
  identity_verified boolean,
  residency_verified boolean,
  work_eligibility public.eligibility_status,
  approved_roles integer,
  verified_skills integer,
  outstanding_training integer,
  failed_vetting integer,
  required_consents_complete boolean,
  deployable boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select wp.*
    from public.worker_profiles wp
    where wp.user_id = auth.uid()
  ), role_count as (
    select count(*)::int as n
    from public.worker_roles wr
    join public.roles r on r.id = wr.role_id
    where wr.worker_id = auth.uid()
      and wr.approved = true
      and r.active = true
  ), skill_count as (
    select count(*)::int as n
    from public.worker_skills ws
    join public.skills s on s.id = ws.skill_id
    where ws.worker_id = auth.uid()
      and ws.verified = true
      and s.active = true
  ), training_count as (
    select count(*)::int as n
    from public.training_modules tm
    where tm.active = true
      and (
        tm.role_id is null
        or exists (
          select 1
          from public.worker_roles wr
          where wr.worker_id = auth.uid()
            and wr.role_id = tm.role_id
            and wr.approved = true
        )
      )
      and not exists (
        select 1
        from public.worker_training wt
        where wt.worker_id = auth.uid()
          and wt.module_id = tm.id
          and wt.status = 'passed'
          and (wt.expires_at is null or wt.expires_at > now())
      )
  ), vetting_count as (
    select count(*)::int as n
    from public.worker_vetting wv
    where wv.worker_id = auth.uid()
      and wv.status in ('pending','failed','manual_review')
  ), current_state as (
    select
      public.worker_has_current_residency(auth.uid()) as residency_ok,
      public.worker_has_current_work_eligibility(auth.uid()) as eligibility_ok,
      (
        public.worker_has_current_consent(auth.uid(),'identity_verification')
        and public.worker_has_current_consent(auth.uid(),'work_eligibility')
        and public.worker_has_current_consent(auth.uid(),'location_clocking')
      ) as consent_ok,
      public.worker_has_deployment_prerequisites(auth.uid()) as deployable
  )
  select
    me.status,
    me.identity_verified,
    current_state.residency_ok,
    case
      when current_state.eligibility_ok then 'eligible'::public.eligibility_status
      when me.work_eligibility in ('ineligible','manual_review') then me.work_eligibility
      else 'unknown'::public.eligibility_status
    end,
    role_count.n,
    skill_count.n,
    training_count.n,
    vetting_count.n,
    current_state.consent_ok,
    current_state.deployable
  from me, role_count, skill_count, training_count, vetting_count, current_state;
$$;

revoke all on function public.get_worker_readiness() from public;
grant execute on function public.get_worker_readiness() to authenticated;

comment on function public.get_worker_readiness() is
'Worker-facing readiness summary aligned with the authoritative live deployability predicate. Residency and work eligibility are evaluated independently using current evidence; required consents use current policy versions.';
