-- Public lead intake for QY Workforce.
-- Deliberately stores only the minimum information required to respond to an enquiry.

create table if not exists public.employer_leads (
  id uuid primary key default gen_random_uuid(),
  company_name text not null check (char_length(company_name) between 2 and 160),
  contact_name text not null check (char_length(contact_name) between 2 and 120),
  email text not null check (char_length(email) <= 254),
  phone text check (phone is null or char_length(phone) <= 32),
  industry text check (industry is null or char_length(industry) <= 80),
  manpower_need text check (manpower_need is null or char_length(manpower_need) <= 1000),
  consent_at timestamptz not null,
  source text not null default 'website' check (char_length(source) <= 80),
  created_at timestamptz not null default now()
);

create table if not exists public.worker_interest_leads (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(full_name) between 2 and 120),
  email text not null check (char_length(email) <= 254),
  phone text check (phone is null or char_length(phone) <= 32),
  work_interest text check (work_interest is null or char_length(work_interest) <= 200),
  consent_at timestamptz not null,
  source text not null default 'website' check (char_length(source) <= 80),
  created_at timestamptz not null default now()
);

alter table public.employer_leads enable row level security;
alter table public.worker_interest_leads enable row level security;

-- Public visitors must not receive direct table read access. Intake should go through
-- server-side handlers/service-role code with rate limiting, bot protection and validation.
revoke all on public.employer_leads from anon, authenticated;
revoke all on public.worker_interest_leads from anon, authenticated;

grant select on public.employer_leads to service_role;
grant insert on public.employer_leads to service_role;
grant select on public.worker_interest_leads to service_role;
grant insert on public.worker_interest_leads to service_role;

create index if not exists employer_leads_created_idx on public.employer_leads (created_at desc);
create index if not exists worker_interest_leads_created_idx on public.worker_interest_leads (created_at desc);

comment on table public.employer_leads is 'Data-minimised employer enquiries captured from approved public channels.';
comment on table public.worker_interest_leads is 'Pre-registration worker interest only; identity verification is performed separately.';
