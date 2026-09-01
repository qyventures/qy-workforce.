-- QY Workforce PDPA rights workflow.
-- Records and controls access/correction/deletion requests without automatically disclosing or deleting data.
-- Any disclosure, correction or deletion remains a reviewed human decision and must respect legal/operational retention obligations.

create table if not exists public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id),
  request_type text not null check (request_type in ('access','correction','deletion')),
  status text not null default 'submitted' check (status in ('submitted','identity_verified','in_review','approved','partially_approved','rejected','completed','withdrawn')),
  request_details text,
  correction_target text,
  assigned_to uuid references public.profiles(id),
  decision_reason text,
  legal_hold boolean not null default false,
  legal_hold_reason text,
  requested_at timestamptz not null default now(),
  verified_at timestamptz,
  decided_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (request_details is null or char_length(request_details) <= 4000),
  check (correction_target is null or char_length(correction_target) <= 400),
  check (decision_reason is null or char_length(decision_reason) <= 2000),
  check (legal_hold_reason is null or char_length(legal_hold_reason) <= 1000),
  check (not legal_hold or nullif(trim(legal_hold_reason),'') is not null)
);

create table if not exists public.privacy_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.privacy_requests(id) on delete restrict,
  actor_id uuid references public.profiles(id),
  event_type text not null check (event_type in ('submitted','identity_verified','assigned','review_started','approved','partially_approved','rejected','completed','withdrawn','legal_hold_set','legal_hold_cleared','note')),
  note text,
  created_at timestamptz not null default now(),
  check (note is null or char_length(note) <= 2000)
);

create index if not exists privacy_requests_requester_idx on public.privacy_requests(requester_id,requested_at desc);
create index if not exists privacy_requests_queue_idx on public.privacy_requests(status,requested_at);
create index if not exists privacy_request_events_request_idx on public.privacy_request_events(request_id,created_at);

alter table public.privacy_requests enable row level security;
alter table public.privacy_request_events enable row level security;

revoke insert,update,delete on public.privacy_requests from anon,authenticated;
revoke insert,update,delete on public.privacy_request_events from anon,authenticated;

create policy "workers read own privacy requests" on public.privacy_requests
  for select using (requester_id=auth.uid() or public.current_app_role() in ('admin','auditor'));
create policy "workers read own privacy request events" on public.privacy_request_events
  for select using (
    exists(select 1 from public.privacy_requests r where r.id=request_id and (r.requester_id=auth.uid() or public.current_app_role() in ('admin','auditor')))
  );

create or replace function public.submit_my_privacy_request(
  p_request_type text,
  p_request_details text default null,
  p_correction_target text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'profile required'; end if;
  if p_request_type not in ('access','correction','deletion') then raise exception 'invalid request type'; end if;
  if p_request_details is not null and char_length(p_request_details)>4000 then raise exception 'request details too long'; end if;
  if p_correction_target is not null and char_length(p_correction_target)>400 then raise exception 'correction target too long'; end if;
  if p_request_type='correction' and nullif(trim(coalesce(p_correction_target,'')),'') is null then raise exception 'correction target required'; end if;

  if exists(select 1 from public.privacy_requests where requester_id=auth.uid() and request_type=p_request_type and status not in ('completed','rejected','withdrawn')) then
    raise exception 'an open request of this type already exists';
  end if;

  insert into public.privacy_requests(requester_id,request_type,request_details,correction_target)
  values(auth.uid(),p_request_type,nullif(trim(p_request_details),''),nullif(trim(p_correction_target),''))
  returning id into v_id;

  insert into public.privacy_request_events(request_id,actor_id,event_type,note)
  values(v_id,auth.uid(),'submitted',null);
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'privacy.request_submitted','privacy_request',v_id,jsonb_build_object('request_type',p_request_type));
  return v_id;
end $$;

create or replace function public.withdraw_my_privacy_request(p_request_id uuid, p_reason text default null)
returns void
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_reason is not null and char_length(p_reason)>1000 then raise exception 'reason too long'; end if;
  update public.privacy_requests set status='withdrawn',updated_at=now()
   where id=p_request_id and requester_id=auth.uid() and status in ('submitted','identity_verified','in_review');
  if not found then raise exception 'request not found or cannot be withdrawn'; end if;
  insert into public.privacy_request_events(request_id,actor_id,event_type,note)
  values(p_request_id,auth.uid(),'withdrawn',nullif(trim(p_reason),''));
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'privacy.request_withdrawn','privacy_request',p_request_id,'{}'::jsonb);
end $$;

create or replace function public.admin_transition_privacy_request(
  p_request_id uuid,
  p_status text,
  p_note text default null,
  p_assigned_to uuid default null,
  p_legal_hold boolean default null,
  p_legal_hold_reason text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare v_old text; v_event text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role()<>'admin' then raise exception 'admin required'; end if;
  if p_note is not null and char_length(p_note)>2000 then raise exception 'note too long'; end if;
  if p_legal_hold_reason is not null and char_length(p_legal_hold_reason)>1000 then raise exception 'legal hold reason too long'; end if;
  select status into v_old from public.privacy_requests where id=p_request_id for update;
  if v_old is null then raise exception 'request not found'; end if;
  if p_status not in ('submitted','identity_verified','in_review','approved','partially_approved','rejected','completed','withdrawn') then raise exception 'invalid status'; end if;

  if not (
    (v_old='submitted' and p_status in ('identity_verified','withdrawn')) or
    (v_old='identity_verified' and p_status in ('in_review','withdrawn')) or
    (v_old='in_review' and p_status in ('approved','partially_approved','rejected','withdrawn')) or
    (v_old in ('approved','partially_approved') and p_status='completed') or
    (v_old=p_status)
  ) then raise exception 'invalid privacy request transition'; end if;

  if p_legal_hold=true and nullif(trim(coalesce(p_legal_hold_reason,'')),'') is null then raise exception 'legal hold reason required'; end if;
  if p_status='completed' and coalesce((select legal_hold from public.privacy_requests where id=p_request_id),false) then raise exception 'cannot complete while legal hold is active'; end if;

  update public.privacy_requests set
    status=p_status,
    assigned_to=coalesce(p_assigned_to,assigned_to),
    decision_reason=case when p_status in ('approved','partially_approved','rejected') then nullif(trim(p_note),'') else decision_reason end,
    legal_hold=coalesce(p_legal_hold,legal_hold),
    legal_hold_reason=case when p_legal_hold=true then trim(p_legal_hold_reason) when p_legal_hold=false then null else legal_hold_reason end,
    verified_at=case when p_status='identity_verified' then coalesce(verified_at,now()) else verified_at end,
    decided_at=case when p_status in ('approved','partially_approved','rejected') then coalesce(decided_at,now()) else decided_at end,
    completed_at=case when p_status='completed' then coalesce(completed_at,now()) else completed_at end,
    updated_at=now()
  where id=p_request_id;

  v_event := case p_status when 'identity_verified' then 'identity_verified' when 'in_review' then 'review_started' else p_status end;
  if v_old<>p_status then
    insert into public.privacy_request_events(request_id,actor_id,event_type,note)
    values(p_request_id,auth.uid(),v_event,nullif(trim(p_note),''));
  elsif p_note is not null then
    insert into public.privacy_request_events(request_id,actor_id,event_type,note)
    values(p_request_id,auth.uid(),'note',nullif(trim(p_note),''));
  end if;
  if p_legal_hold is not null then
    insert into public.privacy_request_events(request_id,actor_id,event_type,note)
    values(p_request_id,auth.uid(),case when p_legal_hold then 'legal_hold_set' else 'legal_hold_cleared' end,nullif(trim(p_legal_hold_reason),''));
  end if;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'privacy.request_transitioned','privacy_request',p_request_id,jsonb_build_object('from',v_old,'to',p_status,'legal_hold',p_legal_hold));
end $$;

revoke all on function public.submit_my_privacy_request(text,text,text) from public;
revoke all on function public.withdraw_my_privacy_request(uuid,text) from public;
revoke all on function public.admin_transition_privacy_request(uuid,text,text,uuid,boolean,text) from public;
grant execute on function public.submit_my_privacy_request(text,text,text) to authenticated;
grant execute on function public.withdraw_my_privacy_request(uuid,text) to authenticated;
grant execute on function public.admin_transition_privacy_request(uuid,text,text,uuid,boolean,text) to authenticated;

comment on table public.privacy_requests is 'Auditable access/correction/deletion workflow. A request never automatically discloses, modifies or deletes personal data.';
comment on table public.privacy_request_events is 'Append-only operational history for privacy-rights requests.';
