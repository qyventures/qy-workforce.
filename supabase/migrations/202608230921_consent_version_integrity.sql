-- QY Workforce: consent version integrity and worker-safe consent RPCs.
-- Consent history remains append-oriented, but workers may no longer forge timestamps,
-- sources, withdrawal state, or arbitrary policy versions through direct table inserts.

create table if not exists public.consent_policy_versions (
  purpose text not null check (purpose in ('identity_verification','work_eligibility','location_clocking','communications','analytics')),
  policy_version text not null check (length(btrim(policy_version)) between 1 and 80),
  effective_at timestamptz not null default now(),
  retired_at timestamptz,
  is_current boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (purpose, policy_version),
  check (retired_at is null or retired_at >= effective_at)
);

create unique index if not exists consent_policy_one_current_per_purpose
  on public.consent_policy_versions(purpose)
  where is_current;

alter table public.consent_policy_versions enable row level security;

create policy "authenticated read current consent policies"
on public.consent_policy_versions
for select to authenticated
using (is_current and effective_at <= now() and (retired_at is null or retired_at > now()));

create policy "admins read all consent policies"
on public.consent_policy_versions
for select to authenticated
using (public.current_app_role() = 'admin');

-- Bootstrap the registry from the latest consent version already observed for each
-- purpose, preserving existing deployments. Missing purposes start at v1.
insert into public.consent_policy_versions(purpose, policy_version, effective_at, is_current)
select distinct on (c.purpose)
  c.purpose,
  c.policy_version,
  least(c.recorded_at, now()),
  true
from public.worker_consents c
where c.policy_version is not null and btrim(c.policy_version) <> ''
order by c.purpose, c.recorded_at desc, c.id desc
on conflict (purpose, policy_version) do nothing;

insert into public.consent_policy_versions(purpose, policy_version, effective_at, is_current)
select p.purpose, 'v1', now(), true
from (values
  ('identity_verification'::text),
  ('work_eligibility'::text),
  ('location_clocking'::text),
  ('communications'::text),
  ('analytics'::text)
) as p(purpose)
where not exists (
  select 1 from public.consent_policy_versions cp
  where cp.purpose = p.purpose and cp.is_current
)
on conflict (purpose, policy_version) do nothing;

-- Remove the old direct worker insert path. Consent writes now pass through RPCs so
-- the server owns actor, source and timestamps.
drop policy if exists "workers create own consents" on public.worker_consents;
revoke insert, update, delete on public.worker_consents from authenticated;

create or replace function public.worker_has_current_consent(
  p_worker_id uuid,
  p_purpose text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.consent_policy_versions cp
    join public.worker_consents c
      on c.worker_id = p_worker_id
     and c.purpose = cp.purpose
     and c.policy_version = cp.policy_version
    where cp.purpose = p_purpose
      and cp.is_current
      and cp.effective_at <= now()
      and (cp.retired_at is null or cp.retired_at > now())
      and c.granted = true
      and c.withdrawn_at is null
  );
$$;

revoke all on function public.worker_has_current_consent(uuid,text) from public;

create or replace function public.grant_worker_consent(
  p_purpose text,
  p_policy_version text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid := auth.uid();
  v_id uuid;
begin
  if v_worker is null then raise exception 'authentication required'; end if;
  if p_purpose not in ('identity_verification','work_eligibility','location_clocking','communications','analytics') then
    raise exception 'unsupported consent purpose';
  end if;

  if not exists (
    select 1 from public.consent_policy_versions cp
    where cp.purpose = p_purpose
      and cp.policy_version = p_policy_version
      and cp.is_current
      and cp.effective_at <= now()
      and (cp.retired_at is null or cp.retired_at > now())
  ) then
    raise exception 'consent policy version is not current';
  end if;

  -- Close any older active grants for the same purpose before recording the current grant.
  update public.worker_consents
     set withdrawn_at = now()
   where worker_id = v_worker
     and purpose = p_purpose
     and granted = true
     and withdrawn_at is null;

  insert into public.worker_consents(
    worker_id,purpose,policy_version,granted,recorded_at,withdrawn_at,source
  ) values (
    v_worker,p_purpose,p_policy_version,true,now(),null,'worker_app'
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_worker,'consent.granted','worker_consent',v_id,
    jsonb_build_object('purpose',p_purpose,'policy_version',p_policy_version));

  return v_id;
end;
$$;

revoke all on function public.grant_worker_consent(text,text) from public;
grant execute on function public.grant_worker_consent(text,text) to authenticated;

create or replace function public.withdraw_worker_consent(p_purpose text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid := auth.uid();
  v_version text;
  v_count integer;
  v_id uuid;
begin
  if v_worker is null then raise exception 'authentication required'; end if;
  if p_purpose not in ('identity_verification','work_eligibility','location_clocking','communications','analytics') then
    raise exception 'unsupported consent purpose';
  end if;

  select cp.policy_version into v_version
  from public.consent_policy_versions cp
  where cp.purpose = p_purpose and cp.is_current
    and cp.effective_at <= now()
    and (cp.retired_at is null or cp.retired_at > now());

  if v_version is null then raise exception 'no current consent policy'; end if;

  update public.worker_consents
     set withdrawn_at = now()
   where worker_id = v_worker
     and purpose = p_purpose
     and granted = true
     and withdrawn_at is null;
  get diagnostics v_count = row_count;

  insert into public.worker_consents(
    worker_id,purpose,policy_version,granted,recorded_at,withdrawn_at,source
  ) values (
    v_worker,p_purpose,v_version,false,now(),now(),'worker_app'
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_worker,'consent.withdrawn','worker_consent',v_id,
    jsonb_build_object('purpose',p_purpose,'policy_version',v_version,'active_grants_closed',v_count));

  return v_count;
end;
$$;

revoke all on function public.withdraw_worker_consent(text) from public;
grant execute on function public.withdraw_worker_consent(text) to authenticated;

-- Re-issue the authoritative deployment prerequisite predicate so required consent
-- must match the current policy version, not merely any historical grant.
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
      and wp.residency_verified
      and wp.work_eligibility = 'eligible'
      and wp.status not in ('suspended','rejected')
      and exists (
        select 1 from public.worker_roles wr
        join public.roles r on r.id = wr.role_id
        where wr.worker_id = wp.user_id and wr.approved and r.active
      )
      and not exists (
        select 1 from public.worker_vetting wv
        where wv.worker_id = wp.user_id
          and wv.status in ('pending','failed','manual_review')
      )
      and not exists (
        select 1 from public.training_modules tm
        where tm.active
          and (tm.role_id is null or exists (
            select 1 from public.worker_roles wr
            where wr.worker_id = wp.user_id and wr.role_id = tm.role_id and wr.approved
          ))
          and not exists (
            select 1 from public.worker_training wt
            where wt.worker_id = wp.user_id and wt.module_id = tm.id
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

comment on table public.consent_policy_versions is
'Versioned consent-purpose registry. Exactly one current version per purpose; workers can only grant the current effective version through RPC.';
comment on function public.grant_worker_consent(text,text) is
'Server-authoritative worker consent grant. Prevents forged timestamps/source and rejects stale policy versions.';
comment on function public.withdraw_worker_consent(text) is
'Immediately closes all active grants for a purpose, records withdrawal history, and audits the action.';
