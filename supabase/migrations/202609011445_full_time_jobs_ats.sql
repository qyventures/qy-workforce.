-- QY Workforce: full-time jobs and applicant tracking.
-- Complements ad-hoc shifts with controlled vacancy publishing and human-reviewed applications.

create table if not exists public.full_time_jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete restrict,
  site_id uuid references public.sites(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  title text not null,
  description text not null,
  requirements text,
  employment_type text not null default 'full_time' check (employment_type in ('full_time','part_time','contract','permanent')),
  workplace_mode text not null default 'onsite' check (workplace_mode in ('onsite','hybrid','remote')),
  location_text text,
  headcount integer not null default 1 check (headcount between 1 and 500),
  salary_min numeric(12,2),
  salary_max numeric(12,2),
  salary_period text check (salary_period is null or salary_period in ('hour','day','month','year')),
  currency text not null default 'SGD' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'draft' check (status in ('draft','published','hidden','closed')),
  published_at timestamptz,
  closes_at timestamptz,
  created_by uuid not null references public.profiles(id),
  closed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(title)) between 3 and 200),
  check (char_length(trim(description)) between 20 and 10000),
  check (requirements is null or char_length(requirements) <= 10000),
  check (location_text is null or char_length(location_text) <= 300),
  check (salary_min is null or salary_min >= 0),
  check (salary_max is null or salary_max >= 0),
  check (salary_min is null or salary_max is null or salary_max >= salary_min),
  check ((salary_min is null and salary_max is null and salary_period is null) or salary_period is not null)
);

create index if not exists full_time_jobs_status_idx on public.full_time_jobs(status, published_at desc);
create index if not exists full_time_jobs_client_role_idx on public.full_time_jobs(client_id, role_id, status);

create table if not exists public.full_time_applications (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.full_time_jobs(id) on delete restrict,
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  cover_note text,
  status text not null default 'submitted' check (status in ('submitted','screening','shortlisted','interview','offer_review','selected','rejected','withdrawn')),
  submitted_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  last_reviewed_by uuid references public.profiles(id),
  last_reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(job_id, worker_id),
  check (cover_note is null or char_length(cover_note) <= 4000)
);

create index if not exists full_time_applications_job_status_idx on public.full_time_applications(job_id, status, submitted_at);
create index if not exists full_time_applications_worker_idx on public.full_time_applications(worker_id, submitted_at desc);

create table if not exists public.full_time_application_events (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.full_time_applications(id) on delete restrict,
  from_status text,
  to_status text not null,
  note text,
  actor_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (note is null or char_length(note) <= 2000)
);

create index if not exists full_time_application_events_application_idx on public.full_time_application_events(application_id, created_at);

alter table public.full_time_jobs enable row level security;
alter table public.full_time_applications enable row level security;
alter table public.full_time_application_events enable row level security;

revoke insert, update, delete on public.full_time_jobs from anon, authenticated;
revoke insert, update, delete on public.full_time_applications from anon, authenticated;
revoke insert, update, delete on public.full_time_application_events from anon, authenticated;

grant select on public.full_time_jobs to anon, authenticated;
grant select on public.full_time_applications to authenticated;
grant select on public.full_time_application_events to authenticated;

create policy "published full time jobs are readable" on public.full_time_jobs
for select using (status = 'published' and (closes_at is null or closes_at > now()));

create policy "privileged read all full time jobs" on public.full_time_jobs
for select using (public.is_privileged());

create policy "workers read own full time applications" on public.full_time_applications
for select using (worker_id = auth.uid());

create policy "privileged read full time applications" on public.full_time_applications
for select using (public.is_privileged());

create policy "workers read own full time application events" on public.full_time_application_events
for select using (
  exists(select 1 from public.full_time_applications a where a.id = application_id and a.worker_id = auth.uid())
);

create policy "privileged read full time application events" on public.full_time_application_events
for select using (public.is_privileged());

create or replace function public.create_full_time_job_draft(
  p_role_id uuid,
  p_title text,
  p_description text,
  p_requirements text default null,
  p_client_id uuid default null,
  p_site_id uuid default null,
  p_employment_type text default 'full_time',
  p_workplace_mode text default 'onsite',
  p_location_text text default null,
  p_headcount integer default 1,
  p_salary_min numeric default null,
  p_salary_max numeric default null,
  p_salary_period text default null,
  p_closes_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if not exists(select 1 from public.roles where id=p_role_id and active) then raise exception 'active role not found'; end if;
  if p_client_id is not null and not exists(select 1 from public.clients where id=p_client_id and active) then raise exception 'active client not found'; end if;
  if p_site_id is not null and not exists(select 1 from public.sites where id=p_site_id and active and (p_client_id is null or client_id=p_client_id)) then raise exception 'active site not found for client'; end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 200 then raise exception 'invalid title'; end if;
  if p_description is null or char_length(trim(p_description)) not between 20 and 10000 then raise exception 'invalid description'; end if;
  if p_requirements is not null and char_length(p_requirements) > 10000 then raise exception 'requirements too long'; end if;
  if p_employment_type not in ('full_time','part_time','contract','permanent') then raise exception 'invalid employment type'; end if;
  if p_workplace_mode not in ('onsite','hybrid','remote') then raise exception 'invalid workplace mode'; end if;
  if p_headcount not between 1 and 500 then raise exception 'invalid headcount'; end if;
  if p_salary_min is not null and p_salary_min < 0 then raise exception 'invalid salary minimum'; end if;
  if p_salary_max is not null and p_salary_max < 0 then raise exception 'invalid salary maximum'; end if;
  if p_salary_min is not null and p_salary_max is not null and p_salary_max < p_salary_min then raise exception 'salary maximum below minimum'; end if;
  if (p_salary_min is not null or p_salary_max is not null) and p_salary_period not in ('hour','day','month','year') then raise exception 'salary period required'; end if;
  if p_closes_at is not null and p_closes_at <= now() then raise exception 'closing time must be in the future'; end if;

  insert into public.full_time_jobs(
    client_id,site_id,role_id,title,description,requirements,employment_type,workplace_mode,location_text,
    headcount,salary_min,salary_max,salary_period,closes_at,created_by
  ) values (
    p_client_id,p_site_id,p_role_id,trim(p_title),trim(p_description),nullif(trim(p_requirements),''),p_employment_type,p_workplace_mode,
    nullif(trim(p_location_text),''),p_headcount,p_salary_min,p_salary_max,p_salary_period,p_closes_at,auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'full_time_job.created','full_time_job',v_id,jsonb_build_object('role_id',p_role_id,'client_id',p_client_id,'headcount',p_headcount));
  return v_id;
end $$;
revoke all on function public.create_full_time_job_draft(uuid,text,text,text,uuid,uuid,text,text,text,integer,numeric,numeric,text,timestamptz) from public;
grant execute on function public.create_full_time_job_draft(uuid,text,text,text,uuid,uuid,text,text,text,integer,numeric,numeric,text,timestamptz) to authenticated;

create or replace function public.set_full_time_job_status(p_job_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text; v_closes_at timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_status not in ('published','hidden','closed') then raise exception 'invalid job status'; end if;

  select status,closes_at into v_old,v_closes_at from public.full_time_jobs where id=p_job_id for update;
  if not found then raise exception 'job not found'; end if;
  if v_old='closed' then raise exception 'closed job cannot be reopened'; end if;
  if p_status='published' and v_closes_at is not null and v_closes_at <= now() then raise exception 'job closing time has passed'; end if;
  if p_status='hidden' and v_old not in ('published','draft') then raise exception 'job cannot be hidden from current state'; end if;

  update public.full_time_jobs set
    status=p_status,
    published_at=case when p_status='published' then coalesce(published_at,now()) else published_at end,
    closed_by=case when p_status='closed' then auth.uid() else closed_by end,
    updated_at=now()
  where id=p_job_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'full_time_job.status_changed','full_time_job',p_job_id,jsonb_build_object('from',v_old,'to',p_status));
end $$;
revoke all on function public.set_full_time_job_status(uuid,text) from public;
grant execute on function public.set_full_time_job_status(uuid,text) to authenticated;

create or replace function public.apply_to_full_time_job(p_job_id uuid, p_cover_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_status public.worker_status; v_eligibility public.eligibility_status;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select status,work_eligibility into v_status,v_eligibility from public.worker_profiles where user_id=auth.uid();
  if not found then raise exception 'worker profile required'; end if;
  if v_status in ('suspended','rejected') then raise exception 'worker account is not eligible to apply'; end if;
  if v_eligibility='ineligible' then raise exception 'work eligibility requires review'; end if;
  if p_cover_note is not null and char_length(p_cover_note) > 4000 then raise exception 'cover note too long'; end if;
  if not exists(select 1 from public.full_time_jobs where id=p_job_id and status='published' and (closes_at is null or closes_at > now())) then raise exception 'job is not open for applications'; end if;

  insert into public.full_time_applications(job_id,worker_id,cover_note)
  values(p_job_id,auth.uid(),nullif(trim(p_cover_note),'')) returning id into v_id;
  insert into public.full_time_application_events(application_id,from_status,to_status,note,actor_id)
  values(v_id,null,'submitted',null,auth.uid());
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'full_time_application.submitted','full_time_application',v_id,jsonb_build_object('job_id',p_job_id));
  return v_id;
exception when unique_violation then
  raise exception 'application already exists';
end $$;
revoke all on function public.apply_to_full_time_job(uuid,text) from public;
grant execute on function public.apply_to_full_time_job(uuid,text) to authenticated;

create or replace function public.withdraw_full_time_application(p_application_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select status into v_old from public.full_time_applications where id=p_application_id and worker_id=auth.uid() for update;
  if not found then raise exception 'application not found'; end if;
  if v_old in ('selected','rejected','withdrawn') then raise exception 'application cannot be withdrawn from current state'; end if;
  update public.full_time_applications set status='withdrawn',withdrawn_at=now(),updated_at=now() where id=p_application_id;
  insert into public.full_time_application_events(application_id,from_status,to_status,note,actor_id)
  values(p_application_id,v_old,'withdrawn',null,auth.uid());
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'full_time_application.withdrawn','full_time_application',p_application_id,jsonb_build_object('from',v_old));
end $$;
revoke all on function public.withdraw_full_time_application(uuid) from public;
grant execute on function public.withdraw_full_time_application(uuid) to authenticated;

create or replace function public.review_full_time_application(p_application_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text; v_allowed boolean := false;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_note is not null and char_length(p_note) > 2000 then raise exception 'review note too long'; end if;
  select status into v_old from public.full_time_applications where id=p_application_id for update;
  if not found then raise exception 'application not found'; end if;
  if v_old in ('selected','rejected','withdrawn') then raise exception 'application is final'; end if;

  v_allowed :=
    (v_old='submitted' and p_status in ('screening','shortlisted','rejected')) or
    (v_old='screening' and p_status in ('shortlisted','rejected')) or
    (v_old='shortlisted' and p_status in ('interview','rejected')) or
    (v_old='interview' and p_status in ('offer_review','rejected')) or
    (v_old='offer_review' and p_status in ('selected','rejected'));
  if not v_allowed then raise exception 'invalid application transition'; end if;

  update public.full_time_applications set status=p_status,last_reviewed_by=auth.uid(),last_reviewed_at=now(),updated_at=now() where id=p_application_id;
  insert into public.full_time_application_events(application_id,from_status,to_status,note,actor_id)
  values(p_application_id,v_old,p_status,nullif(trim(p_note),''),auth.uid());
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'full_time_application.reviewed','full_time_application',p_application_id,jsonb_build_object('from',v_old,'to',p_status));
end $$;
revoke all on function public.review_full_time_application(uuid,text,text) from public;
grant execute on function public.review_full_time_application(uuid,text,text) to authenticated;

revoke all on function public.create_full_time_job_draft(uuid,text,text,text,uuid,uuid,text,text,text,integer,numeric,numeric,text,timestamptz) from anon;
revoke all on function public.set_full_time_job_status(uuid,text) from anon;
revoke all on function public.apply_to_full_time_job(uuid,text) from anon;
revoke all on function public.withdraw_full_time_application(uuid) from anon;
revoke all on function public.review_full_time_application(uuid,text,text) from anon;
