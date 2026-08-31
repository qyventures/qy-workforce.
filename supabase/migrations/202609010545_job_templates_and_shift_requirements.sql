-- QY Workforce: reusable job templates and operational shift requirements.
-- Adds YYJobs-parity job setup fields without weakening existing shift acceptance/pay controls.

create table if not exists public.job_templates (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete restrict,
  site_id uuid references public.sites(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  name text not null,
  description text,
  requirements text,
  attire text,
  provided_items text,
  industry text,
  default_headcount integer not null default 1 check (default_headcount between 1 and 500),
  default_worker_rate numeric(10,2) check (default_worker_rate is null or default_worker_rate >= 0),
  default_client_rate numeric(10,2) check (default_client_rate is null or default_client_rate >= 0),
  vip boolean not null default false,
  special_flag text,
  active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(name) between 1 and 160),
  check (description is null or char_length(description) <= 4000),
  check (requirements is null or char_length(requirements) <= 4000),
  check (attire is null or char_length(attire) <= 2000),
  check (provided_items is null or char_length(provided_items) <= 2000),
  check (industry is null or char_length(industry) <= 120),
  check (special_flag is null or char_length(special_flag) <= 500)
);
create index if not exists job_templates_client_site_idx on public.job_templates(client_id, site_id, active);
create index if not exists job_templates_role_idx on public.job_templates(role_id, active);

create table if not exists public.shift_operational_details (
  shift_id uuid primary key references public.shifts(id) on delete restrict,
  template_id uuid references public.job_templates(id) on delete set null,
  title text,
  description text,
  requirements text,
  attire text,
  provided_items text,
  industry text,
  vip boolean not null default false,
  special_flag text,
  publish_visible boolean not null default true,
  worker_acknowledgement_required boolean not null default false,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (title is null or char_length(title) <= 160),
  check (description is null or char_length(description) <= 4000),
  check (requirements is null or char_length(requirements) <= 4000),
  check (attire is null or char_length(attire) <= 2000),
  check (provided_items is null or char_length(provided_items) <= 2000),
  check (industry is null or char_length(industry) <= 120),
  check (special_flag is null or char_length(special_flag) <= 500)
);

alter table public.job_templates enable row level security;
alter table public.shift_operational_details enable row level security;
revoke insert, update, delete on public.job_templates from anon, authenticated;
revoke insert, update, delete on public.shift_operational_details from anon, authenticated;

create policy "privileged read job templates" on public.job_templates
  for select using (public.is_privileged());
create policy "privileged read shift operational details" on public.shift_operational_details
  for select using (public.is_privileged());

create or replace function public.create_job_template(
  p_role_id uuid,
  p_name text,
  p_client_id uuid default null,
  p_site_id uuid default null,
  p_description text default null,
  p_requirements text default null,
  p_attire text default null,
  p_provided_items text default null,
  p_industry text default null,
  p_default_headcount integer default 1,
  p_default_worker_rate numeric default null,
  p_default_client_rate numeric default null,
  p_vip boolean default false,
  p_special_flag text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_name is null or char_length(trim(p_name)) not between 1 and 160 then raise exception 'invalid template name'; end if;
  if p_default_headcount is null or p_default_headcount not between 1 and 500 then raise exception 'invalid headcount'; end if;
  if p_default_worker_rate is not null and p_default_worker_rate < 0 then raise exception 'invalid worker rate'; end if;
  if p_default_client_rate is not null and p_default_client_rate < 0 then raise exception 'invalid client rate'; end if;
  if not exists(select 1 from public.roles where id=p_role_id and active) then raise exception 'role unavailable'; end if;
  if p_client_id is not null and not exists(select 1 from public.clients where id=p_client_id and active) then raise exception 'client unavailable'; end if;
  if p_site_id is not null and not exists(select 1 from public.sites where id=p_site_id and active and (p_client_id is null or client_id=p_client_id)) then raise exception 'site unavailable'; end if;

  insert into public.job_templates(client_id,site_id,role_id,name,description,requirements,attire,provided_items,industry,
    default_headcount,default_worker_rate,default_client_rate,vip,special_flag,created_by)
  values(p_client_id,p_site_id,p_role_id,trim(p_name),nullif(trim(p_description),''),nullif(trim(p_requirements),''),
    nullif(trim(p_attire),''),nullif(trim(p_provided_items),''),nullif(trim(p_industry),''),p_default_headcount,
    p_default_worker_rate,p_default_client_rate,coalesce(p_vip,false),nullif(trim(p_special_flag),''),auth.uid())
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'job_template.created','job_template',v_id,jsonb_build_object('role_id',p_role_id,'client_id',p_client_id,'site_id',p_site_id,'headcount',p_default_headcount,'vip',coalesce(p_vip,false)));
  return v_id;
end $$;
revoke all on function public.create_job_template(uuid,text,uuid,uuid,text,text,text,text,text,integer,numeric,numeric,boolean,text) from public;
grant execute on function public.create_job_template(uuid,text,uuid,uuid,text,text,text,text,text,integer,numeric,numeric,boolean,text) to authenticated;

create or replace function public.create_shift_from_template(
  p_template_id uuid,
  p_site_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_headcount integer default null,
  p_worker_rate numeric default null,
  p_client_rate numeric default null,
  p_publish_visible boolean default true,
  p_worker_acknowledgement_required boolean default false
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_template public.job_templates%rowtype; v_shift_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then raise exception 'invalid shift window'; end if;
  select * into v_template from public.job_templates where id=p_template_id and active for share;
  if not found then raise exception 'template unavailable'; end if;
  if not exists(select 1 from public.sites s where s.id=p_site_id and s.active and (v_template.client_id is null or s.client_id=v_template.client_id)) then raise exception 'site unavailable'; end if;
  if coalesce(p_headcount,v_template.default_headcount) not between 1 and 500 then raise exception 'invalid headcount'; end if;
  if coalesce(p_worker_rate,v_template.default_worker_rate) is not null and coalesce(p_worker_rate,v_template.default_worker_rate) < 0 then raise exception 'invalid worker rate'; end if;
  if coalesce(p_client_rate,v_template.default_client_rate) is not null and coalesce(p_client_rate,v_template.default_client_rate) < 0 then raise exception 'invalid client rate'; end if;

  insert into public.shifts(site_id,role_id,starts_at,ends_at,headcount,worker_rate,client_rate,status,created_by)
  values(p_site_id,v_template.role_id,p_starts_at,p_ends_at,coalesce(p_headcount,v_template.default_headcount),
    coalesce(p_worker_rate,v_template.default_worker_rate),coalesce(p_client_rate,v_template.default_client_rate),'draft',auth.uid())
  returning id into v_shift_id;

  insert into public.shift_operational_details(shift_id,template_id,title,description,requirements,attire,provided_items,industry,vip,special_flag,publish_visible,worker_acknowledgement_required,created_by)
  values(v_shift_id,v_template.id,v_template.name,v_template.description,v_template.requirements,v_template.attire,v_template.provided_items,
    v_template.industry,v_template.vip,v_template.special_flag,coalesce(p_publish_visible,true),coalesce(p_worker_acknowledgement_required,false),auth.uid());

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'shift.created_from_template','shift',v_shift_id,jsonb_build_object('template_id',v_template.id,'site_id',p_site_id,'starts_at',p_starts_at,'ends_at',p_ends_at,'headcount',coalesce(p_headcount,v_template.default_headcount)));
  return v_shift_id;
end $$;
revoke all on function public.create_shift_from_template(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric,boolean,boolean) from public;
grant execute on function public.create_shift_from_template(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric,boolean,boolean) to authenticated;
