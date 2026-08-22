-- QY Workforce V1: audited privacy-request and retention-hold controls
-- This migration deliberately does not hard-delete worker/payroll/audit records.
-- Erasure requests require an authorised retention review before any later anonymisation/purge job.

create table if not exists public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  request_type text not null check (request_type in ('access','export','erasure')),
  status text not null default 'submitted' check (status in ('submitted','in_review','approved','rejected','completed','cancelled')),
  retention_hold boolean not null default false,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  completed_at timestamptz,
  decision_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists privacy_requests_one_open_per_type
  on public.privacy_requests(worker_id, request_type)
  where status in ('submitted','in_review','approved');

create index if not exists privacy_requests_queue_idx
  on public.privacy_requests(status, requested_at);

alter table public.privacy_requests enable row level security;

create policy "workers read own privacy requests" on public.privacy_requests
for select using (worker_id = auth.uid());

create policy "privacy admins read requests" on public.privacy_requests
for select using (public.current_app_role() in ('admin','auditor'));

revoke insert, update, delete on public.privacy_requests from authenticated;

create or replace function public.request_privacy_action(p_request_type text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() <> 'worker' then raise exception 'worker account required'; end if;
  if p_request_type not in ('access','export','erasure') then raise exception 'unsupported privacy request'; end if;
  if not exists (select 1 from public.worker_profiles wp where wp.user_id = auth.uid()) then raise exception 'worker profile not found'; end if;
  if exists (
    select 1 from public.privacy_requests pr
    where pr.worker_id = auth.uid() and pr.request_type = p_request_type
      and pr.status in ('submitted','in_review','approved')
  ) then raise exception 'an active request of this type already exists'; end if;

  insert into public.privacy_requests(worker_id, request_type)
  values (auth.uid(), p_request_type)
  returning id into v_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'privacy_request.submitted', 'privacy_request', v_id,
    jsonb_build_object('request_type', p_request_type));
  return v_id;
end;
$$;

create or replace function public.review_privacy_request(
  p_request uuid,
  p_decision text,
  p_reason text default null,
  p_retention_hold boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker uuid;
  v_type text;
begin
  if public.current_app_role() <> 'admin' then raise exception 'admin required'; end if;
  if p_decision not in ('in_review','approved','rejected','completed','cancelled') then raise exception 'unsupported decision'; end if;
  if p_decision in ('rejected','cancelled') and nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'decision reason required'; end if;

  select worker_id, request_type into v_worker, v_type
  from public.privacy_requests
  where id = p_request
  for update;

  if v_worker is null then raise exception 'privacy request not found'; end if;
  if v_worker = auth.uid() then raise exception 'self-review is not permitted'; end if;
  if not exists (
    select 1 from public.privacy_requests
    where id = p_request and status in ('submitted','in_review','approved')
  ) then raise exception 'privacy request is not reviewable'; end if;
  if p_decision = 'completed' and v_type = 'erasure' and p_retention_hold then
    raise exception 'erasure cannot be completed while retention hold is active';
  end if;

  update public.privacy_requests
  set status = p_decision,
      retention_hold = p_retention_hold,
      reviewed_at = case when p_decision in ('in_review','approved','rejected','cancelled','completed') then now() else reviewed_at end,
      reviewed_by = auth.uid(),
      completed_at = case when p_decision = 'completed' then now() else null end,
      decision_reason = case when p_reason is null then decision_reason else left(trim(p_reason),1000) end,
      updated_at = now()
  where id = p_request;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'privacy_request.reviewed', 'privacy_request', p_request,
    jsonb_build_object('request_type', v_type, 'decision', p_decision, 'retention_hold', p_retention_hold));
end;
$$;

revoke all on function public.request_privacy_action(text) from public;
revoke all on function public.review_privacy_request(uuid,text,text,boolean) from public;
grant execute on function public.request_privacy_action(text) to authenticated;
grant execute on function public.review_privacy_request(uuid,text,text,boolean) to authenticated;

insert into public.data_retention_policies(data_class, retention_days, rationale) values
  ('privacy_requests', 2555, 'Retain request/decision evidence for accountability while minimising decision notes')
on conflict (data_class) do nothing;
