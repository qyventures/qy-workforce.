-- QY Workforce: employer CRM core for contacts, contracts and feedback.
-- Keeps employer relationship data behind privileged reads and audited Ops/Admin mutation RPCs.

create table if not exists public.client_contacts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  name text not null,
  title text,
  email text,
  phone text,
  is_primary boolean not null default false,
  active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(name)) between 1 and 200),
  check (title is null or char_length(title) <= 200),
  check (email is null or char_length(email) <= 320),
  check (phone is null or char_length(phone) <= 40)
);

create unique index if not exists client_contacts_one_primary_idx
  on public.client_contacts(client_id) where is_primary and active;
create index if not exists client_contacts_client_idx on public.client_contacts(client_id, active);

create table if not exists public.client_contracts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  contract_reference text not null,
  starts_on date not null,
  ends_on date,
  status text not null default 'draft' check (status in ('draft','active','expired','terminated')),
  payment_terms_days integer check (payment_terms_days between 0 and 365),
  notes text,
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(client_id, contract_reference),
  check (ends_on is null or ends_on >= starts_on),
  check (char_length(contract_reference) between 1 and 120),
  check (notes is null or char_length(notes) <= 4000)
);
create index if not exists client_contracts_client_status_idx on public.client_contracts(client_id, status, starts_on desc);

create table if not exists public.client_feedback (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  site_id uuid references public.sites(id) on delete set null,
  feedback_type text not null check (feedback_type in ('compliment','issue','service_review','renewal_risk','commercial')),
  severity text not null default 'normal' check (severity in ('low','normal','high','critical')),
  summary text not null,
  details text,
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  owner_id uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(summary)) between 1 and 500),
  check (details is null or char_length(details) <= 5000)
);
create index if not exists client_feedback_client_status_idx on public.client_feedback(client_id, status, severity, created_at desc);

alter table public.client_contacts enable row level security;
alter table public.client_contracts enable row level security;
alter table public.client_feedback enable row level security;

revoke insert, update, delete on public.client_contacts from anon, authenticated;
revoke insert, update, delete on public.client_contracts from anon, authenticated;
revoke insert, update, delete on public.client_feedback from anon, authenticated;

create policy "privileged read client contacts" on public.client_contacts for select using (public.is_privileged());
create policy "privileged read client contracts" on public.client_contracts for select using (public.is_privileged());
create policy "privileged read client feedback" on public.client_feedback for select using (public.is_privileged());

create or replace function public.save_client_contact(
  p_client_id uuid,
  p_name text,
  p_title text default null,
  p_email text default null,
  p_phone text default null,
  p_is_primary boolean default false
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.clients where id=p_client_id and active) then raise exception 'active client not found'; end if;
  if p_name is null or char_length(trim(p_name)) not between 1 and 200 then raise exception 'invalid contact name'; end if;
  if p_email is not null and (char_length(trim(p_email)) > 320 or position('@' in p_email)=0) then raise exception 'invalid email'; end if;
  if p_phone is not null and char_length(trim(p_phone)) > 40 then raise exception 'invalid phone'; end if;
  if p_is_primary then update public.client_contacts set is_primary=false, updated_at=now() where client_id=p_client_id and is_primary and active; end if;
  insert into public.client_contacts(client_id,name,title,email,phone,is_primary,created_by)
  values(p_client_id,trim(p_name),nullif(trim(p_title),''),lower(nullif(trim(p_email),'')),nullif(trim(p_phone),''),coalesce(p_is_primary,false),auth.uid())
  returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'client_contact.created','client_contact',v_id,jsonb_build_object('client_id',p_client_id,'is_primary',coalesce(p_is_primary,false)));
  return v_id;
end $$;
revoke all on function public.save_client_contact(uuid,text,text,text,text,boolean) from public;
grant execute on function public.save_client_contact(uuid,text,text,text,text,boolean) to authenticated;

create or replace function public.create_client_contract(
  p_client_id uuid,
  p_contract_reference text,
  p_starts_on date,
  p_ends_on date default null,
  p_payment_terms_days integer default null,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.clients where id=p_client_id) then raise exception 'client not found'; end if;
  if p_contract_reference is null or char_length(trim(p_contract_reference)) not between 1 and 120 then raise exception 'invalid contract reference'; end if;
  if p_starts_on is null or (p_ends_on is not null and p_ends_on < p_starts_on) then raise exception 'invalid contract dates'; end if;
  if p_payment_terms_days is not null and p_payment_terms_days not between 0 and 365 then raise exception 'invalid payment terms'; end if;
  insert into public.client_contracts(client_id,contract_reference,starts_on,ends_on,payment_terms_days,notes,created_by)
  values(p_client_id,trim(p_contract_reference),p_starts_on,p_ends_on,p_payment_terms_days,nullif(trim(p_notes),''),auth.uid()) returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'client_contract.created','client_contract',v_id,jsonb_build_object('client_id',p_client_id));
  return v_id;
end $$;
revoke all on function public.create_client_contract(uuid,text,date,date,integer,text) from public;
grant execute on function public.create_client_contract(uuid,text,date,date,integer,text) to authenticated;

create or replace function public.record_client_feedback(
  p_client_id uuid,
  p_site_id uuid,
  p_feedback_type text,
  p_severity text,
  p_summary text,
  p_details text default null,
  p_owner_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_feedback_type not in ('compliment','issue','service_review','renewal_risk','commercial') then raise exception 'invalid feedback type'; end if;
  if p_severity not in ('low','normal','high','critical') then raise exception 'invalid severity'; end if;
  if p_summary is null or char_length(trim(p_summary)) not between 1 and 500 then raise exception 'invalid summary'; end if;
  if not exists(select 1 from public.clients where id=p_client_id) then raise exception 'client not found'; end if;
  if p_site_id is not null and not exists(select 1 from public.sites where id=p_site_id and client_id=p_client_id) then raise exception 'site does not belong to client'; end if;
  insert into public.client_feedback(client_id,site_id,feedback_type,severity,summary,details,owner_id,created_by)
  values(p_client_id,p_site_id,p_feedback_type,p_severity,trim(p_summary),nullif(trim(p_details),''),p_owner_id,auth.uid()) returning id into v_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'client_feedback.created','client_feedback',v_id,jsonb_build_object('client_id',p_client_id,'severity',p_severity,'type',p_feedback_type));
  return v_id;
end $$;
revoke all on function public.record_client_feedback(uuid,uuid,text,text,text,text,uuid) from public;
grant execute on function public.record_client_feedback(uuid,uuid,text,text,text,text,uuid) to authenticated;
