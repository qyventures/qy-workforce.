-- QY Workforce: privacy-safe worker readiness summary for the mobile app.
-- Returns only the authenticated worker's own readiness state and non-sensitive counts.

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
    select count(*)::int as n from public.worker_roles wr
    where wr.worker_id = auth.uid() and wr.approved
  ), skill_count as (
    select count(*)::int as n from public.worker_skills ws
    where ws.worker_id = auth.uid() and ws.verified
  ), training_count as (
    select count(*)::int as n from public.worker_training wt
    where wt.worker_id = auth.uid()
      and wt.status not in ('passed')
  ), vetting_count as (
    select count(*)::int as n from public.worker_vetting wv
    where wv.worker_id = auth.uid() and wv.status = 'failed'
  ), consent_state as (
    select (
      exists(select 1 from public.worker_consents c where c.worker_id = auth.uid() and c.purpose='identity_verification' and c.granted and c.withdrawn_at is null)
      and exists(select 1 from public.worker_consents c where c.worker_id = auth.uid() and c.purpose='work_eligibility' and c.granted and c.withdrawn_at is null)
      and exists(select 1 from public.worker_consents c where c.worker_id = auth.uid() and c.purpose='location_clocking' and c.granted and c.withdrawn_at is null)
    ) as ok
  )
  select
    me.status,
    me.identity_verified,
    me.residency_verified,
    me.work_eligibility,
    role_count.n,
    skill_count.n,
    training_count.n,
    vetting_count.n,
    consent_state.ok,
    (
      me.identity_verified
      and me.residency_verified
      and me.work_eligibility = 'eligible'
      and role_count.n > 0
      and training_count.n = 0
      and vetting_count.n = 0
      and consent_state.ok
      and me.status not in ('suspended','rejected')
    ) as deployable
  from me, role_count, skill_count, training_count, vetting_count, consent_state;
$$;

revoke all on function public.get_worker_readiness() from public;
grant execute on function public.get_worker_readiness() to authenticated;
