-- QY Workforce: audited client account ownership and CRM activity timeline.
-- Provides explicit account ownership history and immutable-ish operational activity records
-- without widening client data access beyond privileged roles.

create table if not exists public.client_account_ownership_history (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assignment_reason text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  ended_by uuid references public.profiles(id) on delete restrict,
  end_reason text,
  created_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at),
  check (assignment_reason is null or char_length(assignment_reason) <= 1000),
  check (end_reason is null or char_length(end_reason) <= 1000)
);

create unique index if not exists client_account_one_current_owner_idx
  on public.client_account_ownership_history(client_id)
  where ends_at is null;
create index if not exists client_account_owner_history_client_idx
  on public.client_account_ownership_history(client_id, starts_at desc);
create index if not exists client_account_owner_history_owner_idx
  on public.client_account_ownership_history(owner_id, starts_at desc);

create table if not exists public.client_account_activities (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  site_id uuid references public.sites(id) on delete set null,
  contact_id uuid references public.client_contacts(id) on delete set null,
  activity_type text not null check (activity_type in ('call','email','meeting','whatsapp','note','commercial','service','escalation','follow_up')),
  summary text not null,
  outcome text,
  follow_up_at timestamptz,
  owner_id uuid references public.profiles(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (char_length(trim(summary)) between 1 and 1000),
  check (outcome is null or char_length(outcome) <= 4000)
);

create index if not exists client_account_activities_client_idx
  on public.client_account_activities(client_id, created_at desc);
create index if not exists client_account_activities_follow_up_idx
  on public.client_account_activities(follow_up_at)
  where follow_up_at is not null;

alter table public.client_account_ownership_history enable row level security;
alter table public.client_account_activities enable row level security;

revoke insert, update, delete on public.client_account_ownership_history from anon, authenticated;
revoke insert, update, delete on public.client_account_activities from anon, authenticated;

create policy "privileged read client account ownership history"
  on public.client_account_ownership_history
  for select using (public.is_privileged());

create policy "privileged read client account activities"
  on public.client_account_activities
  for select using (public.is_privileged());

create or replace view public.current_client_account_owners as
select h.client_id, h.owner_id, h.assigned_by, h.assignment_reason, h.starts_at
from public.client_account_ownership_history h
where h.ends_at is null;

revoke all on public.current_client_account_owners from public;
grant select on public.current_client_account_owners to authenticated;

create or replace function public.assign_client_account_owner(
  p_client_id uuid,
  p_owner_id uuid,
  p_reason text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_previous_owner uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.clients where id = p_client_id and active) then
    raise exception 'active client not found';
  end if;
  if not exists(
    select 1 from public.profiles
    where id = p_owner_id and role in ('recruiter','ops_manager','admin')
  ) then
    raise exception 'eligible account owner not found';
  end if;
  if p_reason is not null and char_length(p_reason) > 1000 then
    raise exception 'reason too long';
  end if;

  select owner_id into v_previous_owner
  from public.client_account_ownership_history
  where client_id = p_client_id and ends_at is null
  for update;

  if v_previous_owner = p_owner_id then
    raise exception 'owner already assigned';
  end if;

  update public.client_account_ownership_history
     set ends_at = now(),
         ended_by = auth.uid(),
         end_reason = coalesce(nullif(trim(p_reason),''), 'owner reassigned')
   where client_id = p_client_id and ends_at is null;

  insert into public.client_account_ownership_history(
    client_id, owner_id, assigned_by, assignment_reason
  ) values (
    p_client_id, p_owner_id, auth.uid(), nullif(trim(p_reason),'')
  ) returning id into v_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(
    auth.uid(),
    'client_account.owner_assigned',
    'client',
    p_client_id,
    jsonb_build_object(
      'ownership_id', v_id,
      'previous_owner_id', v_previous_owner,
      'new_owner_id', p_owner_id
    )
  );

  return v_id;
end;
$$;

revoke all on function public.assign_client_account_owner(uuid,uuid,text) from public;
grant execute on function public.assign_client_account_owner(uuid,uuid,text) to authenticated;

create or replace function public.record_client_account_activity(
  p_client_id uuid,
  p_activity_type text,
  p_summary text,
  p_outcome text default null,
  p_site_id uuid default null,
  p_contact_id uuid default null,
  p_follow_up_at timestamptz default null,
  p_owner_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_owner uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_activity_type not in ('call','email','meeting','whatsapp','note','commercial','service','escalation','follow_up') then
    raise exception 'invalid activity type';
  end if;
  if p_summary is null or char_length(trim(p_summary)) not between 1 and 1000 then
    raise exception 'invalid summary';
  end if;
  if p_outcome is not null and char_length(p_outcome) > 4000 then
    raise exception 'outcome too long';
  end if;
  if not exists(select 1 from public.clients where id = p_client_id) then
    raise exception 'client not found';
  end if;
  if p_site_id is not null and not exists(
    select 1 from public.sites where id = p_site_id and client_id = p_client_id
  ) then
    raise exception 'site does not belong to client';
  end if;
  if p_contact_id is not null and not exists(
    select 1 from public.client_contacts where id = p_contact_id and client_id = p_client_id
  ) then
    raise exception 'contact does not belong to client';
  end if;

  v_owner := p_owner_id;
  if v_owner is null then
    select owner_id into v_owner
    from public.client_account_ownership_history
    where client_id = p_client_id and ends_at is null;
  end if;
  if v_owner is not null and not exists(select 1 from public.profiles where id = v_owner) then
    raise exception 'owner not found';
  end if;

  insert into public.client_account_activities(
    client_id, site_id, contact_id, activity_type, summary, outcome,
    follow_up_at, owner_id, created_by
  ) values (
    p_client_id, p_site_id, p_contact_id, p_activity_type, trim(p_summary),
    nullif(trim(p_outcome),''), p_follow_up_at, v_owner, auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(
    auth.uid(),
    'client_account.activity_recorded',
    'client_account_activity',
    v_id,
    jsonb_build_object(
      'client_id', p_client_id,
      'activity_type', p_activity_type,
      'has_follow_up', p_follow_up_at is not null
    )
  );

  return v_id;
end;
$$;

revoke all on function public.record_client_account_activity(uuid,text,text,text,uuid,uuid,timestamptz,uuid) from public;
grant execute on function public.record_client_account_activity(uuid,text,text,text,uuid,uuid,timestamptz,uuid) to authenticated;
