-- Secure self-service worker onboarding.
-- Workers do not receive direct write access to privileged profile/status fields.

create table public.worker_role_interests (
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (worker_id, role_id)
);

alter table public.worker_role_interests enable row level security;

create policy "workers read own role interests" on public.worker_role_interests
for select using (worker_id = auth.uid());

create policy "ops read role interests" on public.worker_role_interests
for select using (public.is_privileged());

create or replace function public.complete_worker_onboarding(
  p_display_name text,
  p_role_codes text[],
  p_policy_version text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_name text := nullif(trim(p_display_name), '');
  v_inserted_interests integer := 0;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'display name must be between 2 and 120 characters';
  end if;
  if p_policy_version is null or char_length(trim(p_policy_version)) < 4 then
    raise exception 'policy version required';
  end if;
  if coalesce(array_length(p_role_codes, 1), 0) < 1 then
    raise exception 'at least one work interest required';
  end if;
  if coalesce(array_length(p_role_codes, 1), 0) > 10 then
    raise exception 'too many work interests';
  end if;
  if exists (
    select 1 from unnest(p_role_codes) code
    where not exists (select 1 from public.roles r where r.code = code and r.active)
  ) then
    raise exception 'unsupported work interest';
  end if;

  insert into public.profiles(id, role, display_name, phone)
  values (v_user, 'worker', v_name, null)
  on conflict (id) do update
    set display_name = excluded.display_name,
        updated_at = now()
    where public.profiles.id = v_user and public.profiles.role = 'worker';

  if not exists (select 1 from public.profiles where id = v_user and role = 'worker') then
    raise exception 'account is not a worker account';
  end if;

  insert into public.worker_profiles(user_id)
  values (v_user)
  on conflict (user_id) do nothing;

  delete from public.worker_role_interests where worker_id = v_user;
  insert into public.worker_role_interests(worker_id, role_id)
  select v_user, r.id
  from public.roles r
  where r.active and r.code = any(p_role_codes);
  get diagnostics v_inserted_interests = row_count;

  insert into public.worker_consents(worker_id, purpose, policy_version, granted, source)
  select v_user, purpose, trim(p_policy_version), true, 'worker_app'
  from unnest(array['identity_verification','work_eligibility','location_clocking']) purpose;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    v_user,
    'worker_onboarding_completed',
    'worker_profile',
    v_user,
    jsonb_build_object('policy_version', trim(p_policy_version), 'interest_count', v_inserted_interests)
  );

  return jsonb_build_object(
    'worker_id', v_user,
    'interest_count', v_inserted_interests,
    'policy_version', trim(p_policy_version)
  );
end;
$$;

revoke all on function public.complete_worker_onboarding(text,text[],text) from public;
grant execute on function public.complete_worker_onboarding(text,text[],text) to authenticated;

comment on function public.complete_worker_onboarding(text,text[],text) is
'Creates/updates only safe worker onboarding fields, records role interests and mandatory operational consents, and writes an audit event.';
