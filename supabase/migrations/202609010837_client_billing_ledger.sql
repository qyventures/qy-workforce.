-- Durable client billing ledger built from approved/payroll-ready timesheets.
-- Financial snapshots are immutable; only controlled billing-state metadata may transition.

create table public.client_billing_items (
  id uuid primary key default gen_random_uuid(),
  timesheet_id uuid not null unique references public.timesheets(id) on delete restrict,
  assignment_id uuid not null references public.shift_assignments(id) on delete restrict,
  shift_id uuid not null references public.shifts(id) on delete restrict,
  site_id uuid not null references public.sites(id) on delete restrict,
  client_id uuid not null references public.clients(id) on delete restrict,
  service_date date not null,
  payable_minutes integer not null check (payable_minutes >= 0),
  worker_amount numeric(12,2) not null default 0,
  client_amount numeric(12,2) not null check (client_amount >= 0),
  gross_margin numeric(12,2) generated always as (client_amount-worker_amount) stored,
  billing_status text not null default 'pending'
    check (billing_status in ('pending','invoice_ready','invoiced','paid','disputed')),
  invoice_reference text,
  reconciled_note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  invoice_ready_at timestamptz,
  invoiced_at timestamptz,
  paid_at timestamptz,
  disputed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index client_billing_items_client_status_idx
  on public.client_billing_items(client_id,billing_status,service_date);
create index client_billing_items_site_date_idx
  on public.client_billing_items(site_id,service_date);

alter table public.client_billing_items enable row level security;

create policy "privileged read client billing" on public.client_billing_items
for select using (public.current_app_role() in ('ops_manager','finance','admin','auditor'));

-- No direct authenticated mutations. All writes flow through the RPCs below.
revoke insert, update, delete on public.client_billing_items from anon, authenticated;

after all;