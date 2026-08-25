-- QY Workforce lead qualification funnel.
-- Supabase remains the source of truth for consent, qualification state and conversation history.

alter table public.employer_leads
  add column if not exists deployment_timeline text check (deployment_timeline is null or char_length(deployment_timeline) <= 160),
  add column if not exists roles_headcount text check (roles_headcount is null or char_length(roles_headcount) <= 500),
  add column if not exists location text check (location is null or char_length(location) <= 300),
  add column if not exists requirements text check (requirements is null or char_length(requirements) <= 1000),
  add column if not exists whatsapp_consent_at timestamptz,
  add column if not exists campaign text check (campaign is null or char_length(campaign) <= 120),
  add column if not exists qualification_status text not null default 'new' check (qualification_status in ('new','queued','in_progress','qualified','handoff_ready','closed')),
  add column if not exists ai_summary text check (ai_summary is null or char_length(ai_summary) <= 2000),
  add column if not exists lead_score smallint check (lead_score is null or lead_score between 0 and 100),
  add column if not exists bd_status text not null default 'new' check (bd_status in ('new','assigned','contacted','qualified','won','lost','nurture')),
  add column if not exists bd_owner text check (bd_owner is null or char_length(bd_owner) <= 120),
  add column if not exists next_action text check (next_action is null or char_length(next_action) <= 500),
  add column if not exists follow_up_at timestamptz;

alter table public.worker_interest_leads
  add column if not exists availability text check (availability is null or char_length(availability) <= 500),
  add column if not exists preferred_locations text check (preferred_locations is null or char_length(preferred_locations) <= 300),
  add column if not exists notes text check (notes is null or char_length(notes) <= 1000),
  add column if not exists whatsapp_consent_at timestamptz,
  add column if not exists campaign text check (campaign is null or char_length(campaign) <= 120),
  add column if not exists qualification_status text not null default 'new' check (qualification_status in ('new','queued','in_progress','qualified','handoff_ready','closed')),
  add column if not exists ai_summary text check (ai_summary is null or char_length(ai_summary) <= 2000),
  add column if not exists lead_score smallint check (lead_score is null or lead_score between 0 and 100),
  add column if not exists bd_status text not null default 'new' check (bd_status in ('new','assigned','contacted','qualified','won','lost','nurture')),
  add column if not exists bd_owner text check (bd_owner is null or char_length(bd_owner) <= 120),
  add column if not exists next_action text check (next_action is null or char_length(next_action) <= 500),
  add column if not exists follow_up_at timestamptz;

create table if not exists public.lead_qualification_queue (
  id uuid primary key default gen_random_uuid(),
  lead_type text not null check (lead_type in ('employer','worker')),
  lead_id uuid not null,
  channel text not null default 'whatsapp' check (channel = 'whatsapp'),
  sender text not null default '+6584317050' check (char_length(sender) <= 32),
  status text not null default 'queued' check (status in ('queued','in_progress','waiting_for_reply','qualified','handoff_ready','failed','cancelled')),
  attempts smallint not null default 0 check (attempts between 0 and 20),
  last_error text check (last_error is null or char_length(last_error) <= 500),
  next_attempt_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lead_type, lead_id, channel)
);

create table if not exists public.lead_conversation_messages (
  id uuid primary key default gen_random_uuid(),
  lead_type text not null check (lead_type in ('employer','worker')),
  lead_id uuid not null,
  channel text not null default 'whatsapp' check (channel = 'whatsapp'),
  direction text not null check (direction in ('inbound','outbound','system')),
  provider_message_id text check (provider_message_id is null or char_length(provider_message_id) <= 200),
  message_text text not null check (char_length(message_text) between 1 and 4000),
  created_at timestamptz not null default now()
);

alter table public.lead_qualification_queue enable row level security;
alter table public.lead_conversation_messages enable row level security;

revoke all on public.lead_qualification_queue from anon, authenticated;
revoke all on public.lead_conversation_messages from anon, authenticated;
grant select, insert, update on public.lead_qualification_queue to service_role;
grant select, insert on public.lead_conversation_messages to service_role;

create index if not exists lead_qualification_queue_status_idx
  on public.lead_qualification_queue (status, next_attempt_at, created_at);
create index if not exists lead_conversation_messages_lead_idx
  on public.lead_conversation_messages (lead_type, lead_id, created_at);

comment on table public.lead_qualification_queue is 'Server-only queue for consented QY Workforce WhatsApp qualification.';
comment on table public.lead_conversation_messages is 'Server-only WhatsApp qualification conversation history for consented leads.';
