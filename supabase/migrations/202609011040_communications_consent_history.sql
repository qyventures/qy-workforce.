-- QY Workforce communications consent/history core.
-- Records consent, opt-out, communication evidence and escalation state only.
-- This migration does not send messages or activate any external provider.

create table if not exists public.communication_preferences (
  id uuid primary key default gen_random_uuid(),
  subject_type text not null check (subject_type in ('employer_lead','worker_lead','client_contact','worker')),
  subject_id uuid not null,
  channel text not null check (channel in ('whatsapp','email')),
  status text not null check (status in ('opted_in','opted_out')),
  consent_source text,
  consent_at timestamptz,
  opted_out_at timestamptz,
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(subject_type,subject_id,channel),
  check (consent_source is null or char_length(consent_source) <= 160),
  check ((status='opted_in' and consent_at is not null and opted_out_at is null)
      or (status='opted_out' and opted_out_at is not null))
);

create table if not exists public.communication_events (
  id uuid primary key default gen_random_uuid(),
  subject_type text not null check (subject_type in ('employer_lead','worker_lead','client_contact','worker')),
  subject_id uuid not null,
  channel text not null check (channel in ('whatsapp','email','internal')),
  direction text not null check (direction in ('inbound','outbound','internal')),
  event_type text not null check (event_type in ('attempted','sent','delivered','read','replied','failed','opt_out','note','escalation')),
  summary text,
  external_reference text,
  occurred_at timestamptz not null default now(),
  recorded_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (summary is null or char_length(summary) <= 1200),
  check (external_reference is null or char_length(external_reference) <= 240)
);

create table if not exists public.communication_escalations (
  id uuid primary key default gen_random_uuid(),
  subject_type text not null check (subject_type in ('employer_lead','worker_lead','client_contact','worker')),
  subject_id uuid not null,
  reason text not null,
  severity text not null default 'normal' check (severity in ('low','normal','high','critical')),
  status text not null default 'open' check (status in ('open','acknowledged','resolved','closed')),
  owner_id uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(reason)) between 1 and 1200)
);

create index if not exists communication_events_subject_idx
  on public.communication_events(subject_type,subject_id,occurred_at desc);
create index if not exists communication_escalations_open_idx
  on public.communication_escalations(status,severity,created_at desc);

alter table public.communication_preferences enable row level security;
alter table public.communication_events enable row level security;
alter table public.communication_escalations enable row level security;

revoke insert,update,delete on public.communication_preferences from anon,authenticated;
revoke insert,update,delete on public.communication_events from anon,authenticated;
revoke insert,update,delete on public.communication_escalations from anon,authenticated;

create policy "privileged read communication preferences" on public.communication_preferences
  for select using (public.is_privileged());
create policy "privileged read communication events" on public.communication_events
  for select using (public.is_privileged());
create policy "privileged read communication escalations" on public.communication_escalations
  for select using (public.is_privileged());

create or replace function public.set_communication_preference(
  p_subject_type text,
  p_subject_id uuid,
  p_channel text,
  p_status text,
  p_consent_source text default null,
  p_effective_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_subject_type not in ('employer_lead','worker_lead','client_contact','worker') then raise exception 'invalid subject type'; end if;
  if p_subject_id is null then raise exception 'subject required'; end if;
  if p_channel not in ('whatsapp','email') then raise exception 'invalid channel'; end if;
  if p_status not in ('opted_in','opted_out') then raise exception 'invalid preference'; end if;
  if p_effective_at is null or p_effective_at > now()+interval '5 minutes' then raise exception 'invalid effective time'; end if;
  if p_consent_source is not null and char_length(trim(p_consent_source))>160 then raise exception 'consent source too long'; end if;

  insert into public.communication_preferences(
    subject_type,subject_id,channel,status,consent_source,consent_at,opted_out_at,updated_by,updated_at
  ) values(
    p_subject_type,p_subject_id,p_channel,p_status,nullif(trim(p_consent_source),''),
    case when p_status='opted_in' then p_effective_at else null end,
    case when p_status='opted_out' then p_effective_at else null end,
    auth.uid(),now()
  )
  on conflict(subject_type,subject_id,channel) do update set
    status=excluded.status,
    consent_source=case when excluded.status='opted_in' then excluded.consent_source else communication_preferences.consent_source end,
    consent_at=case when excluded.status='opted_in' then excluded.consent_at else communication_preferences.consent_at end,
    opted_out_at=excluded.opted_out_at,
    updated_by=auth.uid(),updated_at=now()
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'communication.preference_changed','communication_preference',v_id,
         jsonb_build_object('subject_type',p_subject_type,'channel',p_channel,'status',p_status));
  return v_id;
end $$;

revoke all on function public.set_communication_preference(text,uuid,text,text,text,timestamptz) from public;
grant execute on function public.set_communication_preference(text,uuid,text,text,text,timestamptz) to authenticated;

create or replace function public.record_communication_event(
  p_subject_type text,
  p_subject_id uuid,
  p_channel text,
  p_direction text,
  p_event_type text,
  p_summary text default null,
  p_external_reference text default null,
  p_occurred_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_pref text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_subject_type not in ('employer_lead','worker_lead','client_contact','worker') then raise exception 'invalid subject type'; end if;
  if p_subject_id is null then raise exception 'subject required'; end if;
  if p_channel not in ('whatsapp','email','internal') then raise exception 'invalid channel'; end if;
  if p_direction not in ('inbound','outbound','internal') then raise exception 'invalid direction'; end if;
  if p_event_type not in ('attempted','sent','delivered','read','replied','failed','opt_out','note','escalation') then raise exception 'invalid event type'; end if;
  if p_summary is not null and char_length(p_summary)>1200 then raise exception 'summary too long'; end if;
  if p_external_reference is not null and char_length(p_external_reference)>240 then raise exception 'external reference too long'; end if;
  if p_occurred_at is null or p_occurred_at > now()+interval '5 minutes' then raise exception 'invalid event time'; end if;

  -- Outbound WhatsApp/email evidence may only be recorded when explicit opt-in remains active.
  -- This guards future provider hooks from documenting or initiating unsupported outreach paths.
  if p_direction='outbound' and p_channel in ('whatsapp','email') and p_event_type in ('attempted','sent') then
    select status into v_pref from public.communication_preferences
     where subject_type=p_subject_type and subject_id=p_subject_id and channel=p_channel;
    if coalesce(v_pref,'opted_out') <> 'opted_in' then raise exception 'active channel opt-in required'; end if;
  end if;

  insert into public.communication_events(subject_type,subject_id,channel,direction,event_type,summary,external_reference,occurred_at,recorded_by)
  values(p_subject_type,p_subject_id,p_channel,p_direction,p_event_type,nullif(trim(p_summary),''),nullif(trim(p_external_reference),''),p_occurred_at,auth.uid())
  returning id into v_id;

  if p_event_type='opt_out' and p_channel in ('whatsapp','email') then
    insert into public.communication_preferences(subject_type,subject_id,channel,status,consent_at,opted_out_at,updated_by,updated_at)
    values(p_subject_type,p_subject_id,p_channel,'opted_out',null,p_occurred_at,auth.uid(),now())
    on conflict(subject_type,subject_id,channel) do update set status='opted_out',opted_out_at=excluded.opted_out_at,updated_by=auth.uid(),updated_at=now();
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'communication.event_recorded','communication_event',v_id,
         jsonb_build_object('subject_type',p_subject_type,'channel',p_channel,'direction',p_direction,'event_type',p_event_type));
  return v_id;
end $$;

revoke all on function public.record_communication_event(text,uuid,text,text,text,text,text,timestamptz) from public;
grant execute on function public.record_communication_event(text,uuid,text,text,text,text,text,timestamptz) to authenticated;

create or replace function public.create_communication_escalation(
  p_subject_type text,
  p_subject_id uuid,
  p_reason text,
  p_severity text default 'normal',
  p_owner_id uuid default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_subject_type not in ('employer_lead','worker_lead','client_contact','worker') then raise exception 'invalid subject type'; end if;
  if p_subject_id is null then raise exception 'subject required'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 1 and 1200 then raise exception 'invalid reason'; end if;
  if p_severity not in ('low','normal','high','critical') then raise exception 'invalid severity'; end if;
  insert into public.communication_escalations(subject_type,subject_id,reason,severity,owner_id,created_by)
  values(p_subject_type,p_subject_id,trim(p_reason),p_severity,p_owner_id,auth.uid()) returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'communication.escalation_created','communication_escalation',v_id,
         jsonb_build_object('subject_type',p_subject_type,'severity',p_severity));
  return v_id;
end $$;

revoke all on function public.create_communication_escalation(text,uuid,text,text,uuid) from public;
grant execute on function public.create_communication_escalation(text,uuid,text,text,uuid) to authenticated;

comment on table public.communication_preferences is 'Channel consent/opt-out state. Outbound provider integrations must respect this table.';
comment on table public.communication_events is 'Communication evidence/history only; inserting a row does not send a message.';
comment on table public.communication_escalations is 'Human follow-up queue for communication issues and exceptions.';
