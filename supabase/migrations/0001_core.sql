create extension if not exists pgcrypto;

create type public.user_role as enum ('worker','supervisor','recruiter','ops_manager','finance','admin','auditor');
create type public.worker_status as enum ('pending','verified','vetted','trained','deployable','suspended','rejected');
create type public.eligibility_status as enum ('unknown','eligible','ineligible','manual_review');
create type public.shift_status as enum ('draft','open','assigned','in_progress','completed','cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null default 'worker',
  display_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.worker_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  status public.worker_status not null default 'pending',
  identity_verified boolean not null default false,
  identity_provider text,
  identity_verified_at timestamptz,
  residency_category text,
  residency_verified boolean not null default false,
  work_eligibility public.eligibility_status not null default 'unknown',
  eligibility_source text,
  eligibility_checked_at timestamptz,
  preferred_hourly_rate numeric(10,2),
  reliability_score numeric(5,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.skills (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  active boolean not null default true
);

create table public.worker_roles (
  worker_id uuid references public.worker_profiles(user_id) on delete cascade,
  role_id uuid references public.roles(id) on delete cascade,
  approved boolean not null default false,
  approved_at timestamptz,
  approved_by uuid references public.profiles(id),
  primary key(worker_id, role_id)
);

create table public.worker_skills (
  worker_id uuid references public.worker_profiles(user_id) on delete cascade,
  skill_id uuid references public.skills(id) on delete cascade,
  verified boolean not null default false,
  verified_at timestamptz,
  primary key(worker_id, skill_id)
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  name text not null,
  address text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  geofence_radius_m integer not null default 150 check (geofence_radius_m between 25 and 2000),
  active boolean not null default true
);

create table public.shifts (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites(id),
  role_id uuid not null references public.roles(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  headcount integer not null default 1 check (headcount > 0),
  worker_rate numeric(10,2),
  client_rate numeric(10,2),
  status public.shift_status not null default 'draft',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.shift_assignments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references public.shifts(id) on delete cascade,
  worker_id uuid not null references public.worker_profiles(user_id),
  accepted_at timestamptz,
  cancelled_at timestamptz,
  unique(shift_id, worker_id)
);

create table public.time_events (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.shift_assignments(id) on delete cascade,
  event_type text not null check (event_type in ('clock_in','clock_out','break_start','break_end','supervisor_adjustment')),
  occurred_at timestamptz not null default now(),
  latitude numeric(9,6),
  longitude numeric(9,6),
  accuracy_m numeric(8,2),
  within_geofence boolean,
  device_fingerprint_hash text,
  source text not null default 'worker_app',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.timesheets (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.shift_assignments(id) on delete cascade,
  payable_minutes integer not null default 0 check (payable_minutes >= 0),
  worker_amount numeric(12,2),
  client_amount numeric(12,2),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  provider text not null,
  provider_subject_hash text,
  status text not null,
  verified_attributes jsonb not null default '{}'::jsonb,
  consent_recorded_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.worker_profiles enable row level security;
alter table public.worker_roles enable row level security;
alter table public.worker_skills enable row level security;
alter table public.shift_assignments enable row level security;
alter table public.time_events enable row level security;
alter table public.timesheets enable row level security;
alter table public.identity_verifications enable row level security;
alter table public.audit_events enable row level security;

create policy "workers read own profile" on public.profiles
for select using (id = auth.uid());

create policy "workers read own worker profile" on public.worker_profiles
for select using (user_id = auth.uid());

create policy "workers read own role approvals" on public.worker_roles
for select using (worker_id = auth.uid());

create policy "workers read own skills" on public.worker_skills
for select using (worker_id = auth.uid());

create policy "workers read own assignments" on public.shift_assignments
for select using (worker_id = auth.uid());

create policy "workers read own timesheets" on public.timesheets
for select using (
  exists(select 1 from public.shift_assignments a where a.id = assignment_id and a.worker_id = auth.uid())
);

create policy "workers read own verification status" on public.identity_verifications
for select using (worker_id = auth.uid());

-- Privileged policies will be added using app-role claims/service boundaries after auth design is finalised.
-- No broad authenticated-user access is granted here by design.

insert into public.roles(code,name) values
('cleaner','Cleaner'),
('banquet','Banquet Staff'),
('fnb_service','F&B Service Crew'),
('fnb_kitchen','F&B Kitchen Crew'),
('promoter','Promoter / Roadshow Staff'),
('event_crew','Event Crew'),
('retail','Retail Staff');
