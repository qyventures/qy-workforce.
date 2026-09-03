-- Employer lead operational handoff + Sheet delivery observability.
alter table public.employer_leads
  add column if not exists sheet_sync_status text not null default 'pending' check (sheet_sync_status in ('pending','synced','pending_retry','failed')),
  add column if not exists sheet_synced_at timestamptz,
  add column if not exists sheet_sync_error text check (sheet_sync_error is null or char_length(sheet_sync_error) <= 500);

grant update on public.employer_leads to service_role;

create table if not exists public.lead_handoff_events (
  id uuid primary key default gen_random_uuid(),
  lead_type text not null check (lead_type in ('employer','worker')),
  lead_id uuid not null,
  event_type text not null check (event_type in ('hot_lead','human_handoff','sales_review')),
  reason text not null check (char_length(reason) between 1 and 1000),
  lead_score smallint check (lead_score is null or lead_score between 0 and 100),
  status text not null default 'open' check (status in ('open','acknowledged','closed')),
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles(id)
);
alter table public.lead_handoff_events enable row level security;
revoke all on public.lead_handoff_events from anon, authenticated;
grant select, insert, update on public.lead_handoff_events to service_role;
create index if not exists lead_handoff_events_open_idx on public.lead_handoff_events(status, created_at desc);
comment on table public.lead_handoff_events is 'Auditable internal human-handoff events for genuine lead buying intent; never an instruction to contact externally without authorization.';
