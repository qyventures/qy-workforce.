-- Work eligibility is an independently reviewed, time-bounded outcome.
-- Store only an opaque evidence reference; never store document numbers or raw evidence.

alter table public.worker_profiles
  add column if not exists eligibility_expires_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.worker_profiles'::regclass
      and conname = 'worker_profiles_eligibility_validity_check'
  ) then
    alter table public.worker_profiles
      add constraint worker_profiles_eligibility_validity_check
      check (
        (work_eligibility = 'eligible' and eligibility_checked_at is not null and eligibility_expires_at is not null
          and eligibility_expires_at > eligibility_checked_at)
        or
        (work_eligibility <> 'eligible' and eligibility_expires_at is null)
      ) not valid;
  end if;
end;
$$;

create table if not exists public.work_eligibility_reviews (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  status public.eligibility_status not null,
  source text not null,
  evidence_ref text,
  checked_at timestamptz not null,
  valid_until timestamptz,
  reviewed_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (status <> 'unknown'),
  check (char_length(source) between 1 and 100),
  check (evidence_ref is null or char_length(evidence_ref) between 1 and 256),
  check (
    (status = 'eligible' and evidence_ref is not null and valid_until is not null and valid_until > checked_at)
    or
    (status <> 'eligible' and valid_until is null)
  )
);

create index if not exists work_eligibility_reviews_worker_created_idx
  on public.work_eligibility_reviews(worker_id, created_at desc);

create or replace function public.reject_work_eligibility_review_mutation()
returns trigger
language plpgsql
set search_path=pg_catalog,public
as $$
begin
  raise exception 'work eligibility reviews are append-only';
end;
$$;
revoke all on function public.reject_work_eligibility_review_mutation() from public, anon, authenticated;

drop trigger if exists work_eligibility_reviews_append_only on public.work_eligibility_reviews;
create trigger work_eligibility_reviews_append_only
before update or delete on public.work_eligibility_reviews
for each row execute function public.reject_work_eligibility_review_mutation();

alter table public.work_eligibility_reviews enable row level security;
revoke all on table public.work_eligibility_reviews from public, anon, authenticated;
grant select on table public.work_eligibility_reviews to authenticated;

drop policy if exists "privileged read work eligibility reviews" on public.work_eligibility_reviews;
create policy "privileged read work eligibility reviews"
  on public.work_eligibility_reviews for select
  using (public.is_privileged());

-- Retire the earlier non-expiring boundary from API callers. It remains present only
-- so old database clients fail closed with a privilege error instead of writing stale state.
revoke all on function public.record_work_eligibility_staging(uuid,public.eligibility_status,text)
  from public, anon, authenticated;

create or replace function public.record_work_eligibility_staging(
  p_worker uuid,
  p_status public.eligibility_status,
  p_source text,
  p_valid_until timestamptz,
  p_evidence_ref text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor uuid := auth.uid();
  v_source text := nullif(trim(p_source), '');
  v_evidence text := nullif(trim(p_evidence_ref), '');
  v_checked_at timestamptz := clock_timestamp();
begin
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_worker is null or not exists(select 1 from public.worker_profiles where user_id=p_worker) then
    raise exception 'worker profile required';
  end if;
  if p_worker = v_actor then raise exception 'self-review not permitted'; end if;
  if p_status is null or p_status = 'unknown' then raise exception 'review outcome required'; end if;
  if v_source is null or char_length(v_source) > 100 then raise exception 'valid eligibility source required'; end if;
  if v_evidence is not null and char_length(v_evidence) > 256 then raise exception 'evidence reference too long'; end if;
  if p_status = 'eligible' then
    if v_evidence is null then raise exception 'evidence reference required'; end if;
    if p_valid_until is null or p_valid_until <= v_checked_at
       or p_valid_until > v_checked_at + interval '5 years' then
      raise exception 'valid eligibility expiry required';
    end if;
  elsif p_valid_until is not null then
    raise exception 'expiry is only valid for eligible outcome';
  end if;
  if not exists(
    select 1 from public.worker_consents
    where worker_id=p_worker and purpose='work_eligibility'
      and granted and withdrawn_at is null
  ) then raise exception 'work eligibility consent required'; end if;

  perform 1 from public.worker_profiles where user_id=p_worker for update;

  insert into public.work_eligibility_reviews(
    worker_id,status,source,evidence_ref,checked_at,valid_until,reviewed_by
  ) values (
    p_worker,p_status,v_source,v_evidence,v_checked_at,
    case when p_status='eligible' then p_valid_until else null end,v_actor
  );

  update public.worker_profiles
  set work_eligibility=p_status,
      eligibility_source=v_source,
      eligibility_checked_at=v_checked_at,
      eligibility_expires_at=case when p_status='eligible' then p_valid_until else null end,
      updated_at=v_checked_at
  where user_id=p_worker;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(v_actor,'work_eligibility.recorded','worker_profile',p_worker,
    jsonb_build_object('status',p_status,'source',v_source,
      'valid_until',case when p_status='eligible' then p_valid_until else null end,
      'evidence_present',v_evidence is not null));
end;
$$;

revoke all on function public.record_work_eligibility_staging(uuid,public.eligibility_status,text,timestamptz,text)
  from public, anon;
grant execute on function public.record_work_eligibility_staging(uuid,public.eligibility_status,text,timestamptz,text)
  to authenticated;

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
      and wp.eligibility_checked_at is not null
      and wp.eligibility_expires_at > now()
      and wp.status not in ('suspended','rejected')
      and exists (
        select 1 from public.worker_roles wr join public.roles r on r.id=wr.role_id
        where wr.worker_id=wp.user_id and wr.approved and r.active
      )
      and not exists (
        select 1 from public.worker_vetting wv
        where wv.worker_id=wp.user_id and wv.status in ('pending','failed','manual_review')
      )
      and not exists (
        select 1 from public.training_modules tm
        where tm.active
          and (tm.role_id is null or exists (
            select 1 from public.worker_roles wr
            where wr.worker_id=wp.user_id and wr.role_id=tm.role_id and wr.approved
          ))
          and not exists (
            select 1 from public.worker_training wt
            where wt.worker_id=wp.user_id and wt.module_id=tm.id and wt.status='passed'
              and (wt.expires_at is null or wt.expires_at > now())
          )
      )
      and not exists (
        select 1 from (values ('identity_verification'),('work_eligibility'),('location_clocking')) required(purpose)
        where not exists (
          select 1 from public.worker_consents c
          where c.worker_id=wp.user_id and c.purpose=required.purpose
            and c.granted and c.withdrawn_at is null
        )
      )
    from public.worker_profiles wp where wp.user_id=p_worker_id
  ), false);
$$;

revoke all on function public.worker_has_deployment_prerequisites(uuid) from public, anon, authenticated;

comment on column public.worker_profiles.eligibility_expires_at is
  'Expiry of the independently reviewed work-eligibility outcome; unrelated to identity or residency.';
comment on table public.work_eligibility_reviews is
  'Immutable work-eligibility review history containing normalized outcomes and opaque evidence references only.';
comment on function public.record_work_eligibility_staging(uuid,public.eligibility_status,text,timestamptz,text) is
  'Ops-only staging eligibility review with consent, separation of duties, bounded validity, opaque evidence and audit history.';
