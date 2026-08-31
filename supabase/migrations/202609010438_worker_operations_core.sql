-- QY Workforce: worker operations core.
-- Adds worker availability, absence/MC tracking and auditable reliability observations.
-- Sensitive operational mutations remain behind worker-self or Ops/Admin RPC boundaries.

create table if not exists public.worker_availability (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.profiles(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  availability_type text not null default 'available'
    check (availability_type in ('available','unavailable','preferred')),
  notes text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (ends_at <= starts_at + interval '90 days'),
  check (notes is null or char_length(notes) <= 1000)
);
create index if not exists worker_availability_worker_time_idx
  on public.worker_availability(worker_id, starts_at, ends_at);

create table if not exists public.worker_absences (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.profiles(id) on delete restrict,
  absence_type text not null
    check (absence_type in ('medical','leave','emergency','other')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'reported'
    check (status in ('reported','reviewed','approved','rejected','cancelled')),
  reason text,
  document_reference text,
  created_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (ends_at <= starts_at + interval '90 days'),
  check (reason is null or char_length(reason) <= 2000),
  check (document_reference is null or char_length(document_reference) <= 500)
);
create index if not exists worker_absences_worker_status_idx
  on public.worker_absences(worker_id, status, starts_at desc);

create table if not exists public.worker_reliability_events (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null
    check (event_type in ('positive_feedback','late','no_show','cancellation','attendance_exception','client_issue','commendation','manual_adjustment')),
  points integer not null check (points between -20 and 20),
  source_type text not null default 'ops'
    check (source_type in ('system','ops','client_feedback')),
  source_id uuid,
  note text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (note is null or char_length(note) <= 2000)
);
create index if not exists worker_reliability_events_worker_idx
  on public.worker_reliability_events(worker_id, created_at desc);

alter table public.worker_availability enable row level security;
alter table public.worker_absences enable row level security;
alter table public.worker_reliability_events enable row level security;

revoke insert, update, delete on public.worker_availability from anon, authenticated;
revoke insert, update, delete on public.worker_absences from anon, authenticated;
revoke insert, update, delete on public.worker_reliability_events from anon, authenticated;

create policy "worker or privileged read availability"
  on public.worker_availability for select
  using (worker_id = auth.uid() or public.is_privileged());
create policy "worker or privileged read absences"
  on public.worker_absences for select
  using (worker_id = auth.uid() or public.is_privileged());
create policy "privileged read reliability events"
  on public.worker_reliability_events for select
  using (public.is_privileged());

create or replace function public.set_worker_availability(
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_availability_type text,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at or p_ends_at > p_starts_at + interval '90 days' then
    raise exception 'invalid availability window';
  end if;
  if p_availability_type not in ('available','unavailable','preferred') then raise exception 'invalid availability type'; end if;
  if p_notes is not null and char_length(p_notes) > 1000 then raise exception 'notes too long'; end if;

  insert into public.worker_availability(worker_id,starts_at,ends_at,availability_type,notes,created_by)
  values(auth.uid(),p_starts_at,p_ends_at,p_availability_type,nullif(trim(p_notes),''),auth.uid())
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_availability.created','worker_availability',v_id,
    jsonb_build_object('type',p_availability_type,'starts_at',p_starts_at,'ends_at',p_ends_at));
  return v_id;
end $$;
revoke all on function public.set_worker_availability(timestamptz,timestamptz,text,text) from public;
grant execute on function public.set_worker_availability(timestamptz,timestamptz,text,text) to authenticated;

create or replace function public.report_worker_absence(
  p_absence_type text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text default null,
  p_document_reference text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_absence_type not in ('medical','leave','emergency','other') then raise exception 'invalid absence type'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at or p_ends_at > p_starts_at + interval '90 days' then
    raise exception 'invalid absence window';
  end if;
  if p_reason is not null and char_length(p_reason) > 2000 then raise exception 'reason too long'; end if;
  if p_document_reference is not null and char_length(p_document_reference) > 500 then raise exception 'document reference too long'; end if;

  insert into public.worker_absences(worker_id,absence_type,starts_at,ends_at,reason,document_reference,created_by)
  values(auth.uid(),p_absence_type,p_starts_at,p_ends_at,nullif(trim(p_reason),''),nullif(trim(p_document_reference),''),auth.uid())
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_absence.reported','worker_absence',v_id,
    jsonb_build_object('type',p_absence_type,'starts_at',p_starts_at,'ends_at',p_ends_at));
  return v_id;
end $$;
revoke all on function public.report_worker_absence(text,timestamptz,timestamptz,text,text) from public;
grant execute on function public.report_worker_absence(text,timestamptz,timestamptz,text,text) to authenticated;

create or replace function public.review_worker_absence(
  p_absence_id uuid,
  p_decision text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_decision not in ('reviewed','approved','rejected','cancelled') then raise exception 'invalid decision'; end if;

  update public.worker_absences
     set status=p_decision, reviewed_by=auth.uid(), reviewed_at=now(), updated_at=now()
   where id=p_absence_id and status in ('reported','reviewed');
  if not found then raise exception 'absence not found or already terminal'; end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_absence.' || p_decision,'worker_absence',p_absence_id,jsonb_build_object('decision',p_decision));
end $$;
revoke all on function public.review_worker_absence(uuid,text) from public;
grant execute on function public.review_worker_absence(uuid,text) to authenticated;

create or replace function public.record_worker_reliability_event(
  p_worker_id uuid,
  p_event_type text,
  p_points integer,
  p_source_type text default 'ops',
  p_source_id uuid default null,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_event_type not in ('positive_feedback','late','no_show','cancellation','attendance_exception','client_issue','commendation','manual_adjustment') then raise exception 'invalid event type'; end if;
  if p_points is null or p_points not between -20 and 20 then raise exception 'invalid points'; end if;
  if p_source_type not in ('system','ops','client_feedback') then raise exception 'invalid source type'; end if;
  if p_note is not null and char_length(p_note) > 2000 then raise exception 'note too long'; end if;
  if not exists(select 1 from public.profiles where id=p_worker_id) then raise exception 'worker not found'; end if;

  insert into public.worker_reliability_events(worker_id,event_type,points,source_type,source_id,note,created_by)
  values(p_worker_id,p_event_type,p_points,p_source_type,p_source_id,nullif(trim(p_note),''),auth.uid()) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_reliability.recorded','worker_reliability_event',v_id,
    jsonb_build_object('worker_id',p_worker_id,'event_type',p_event_type,'points',p_points,'source_type',p_source_type));
  return v_id;
end $$;
revoke all on function public.record_worker_reliability_event(uuid,text,integer,text,uuid,text) from public;
grant execute on function public.record_worker_reliability_event(uuid,text,integer,text,uuid,text) to authenticated;

create or replace function public.get_worker_reliability_summary(p_worker_id uuid)
returns table(score integer, event_count bigint, last_event_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_privileged() then raise exception 'not authorised'; end if;
  return query
  select greatest(0, least(100, 80 + coalesce(sum(e.points),0)))::integer,
         count(e.id), max(e.created_at)
    from public.worker_reliability_events e
   where e.worker_id=p_worker_id
     and e.created_at >= now() - interval '180 days';
end $$;
revoke all on function public.get_worker_reliability_summary(uuid) from public;
grant execute on function public.get_worker_reliability_summary(uuid) to authenticated;
