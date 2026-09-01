-- QY Workforce: human-reviewed AI-assisted requirement structuring.
-- AI suggestions are advisory only and cannot publish shifts, change rates, or bypass Ops approval.

create table if not exists public.requirement_structuring_reviews (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id),
  source_type text not null check (source_type in ('employer_lead','labour_requisition','shift','full_time_job','manual')),
  source_id uuid,
  raw_requirement text not null check (char_length(raw_requirement) between 1 and 8000),
  suggested_structure jsonb not null default '{}'::jsonb,
  model_label text,
  status text not null default 'draft' check (status in ('draft','in_review','approved','rejected')),
  reviewer_id uuid references public.profiles(id),
  review_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (review_note is null or char_length(review_note) <= 2000),
  check (model_label is null or char_length(model_label) <= 120)
);

create table if not exists public.requirement_structuring_events (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.requirement_structuring_reviews(id) on delete restrict,
  actor_id uuid references public.profiles(id),
  event_type text not null check (event_type in ('created','suggestion_updated','review_started','approved','rejected','note')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists requirement_structuring_queue_idx on public.requirement_structuring_reviews(status,created_at desc);
create index if not exists requirement_structuring_source_idx on public.requirement_structuring_reviews(source_type,source_id);
create index if not exists requirement_structuring_events_idx on public.requirement_structuring_events(review_id,created_at);

alter table public.requirement_structuring_reviews enable row level security;
alter table public.requirement_structuring_events enable row level security;
revoke insert,update,delete on public.requirement_structuring_reviews from anon,authenticated;
revoke insert,update,delete on public.requirement_structuring_events from anon,authenticated;

create policy "ops read requirement structuring" on public.requirement_structuring_reviews
  for select using (public.is_ops());
create policy "ops read requirement structuring events" on public.requirement_structuring_events
  for select using (public.is_ops());

create or replace function public.ops_create_requirement_structuring_review(
  p_source_type text,
  p_source_id uuid,
  p_raw_requirement text,
  p_suggested_structure jsonb default '{}'::jsonb,
  p_model_label text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_source_type not in ('employer_lead','labour_requisition','shift','full_time_job','manual') then raise exception 'invalid source type'; end if;
  if nullif(trim(coalesce(p_raw_requirement,'')),'') is null or char_length(p_raw_requirement)>8000 then raise exception 'invalid raw requirement'; end if;
  if jsonb_typeof(coalesce(p_suggested_structure,'{}'::jsonb)) <> 'object' then raise exception 'suggested structure must be an object'; end if;

  insert into public.requirement_structuring_reviews(created_by,source_type,source_id,raw_requirement,suggested_structure,model_label)
  values(auth.uid(),p_source_type,p_source_id,trim(p_raw_requirement),coalesce(p_suggested_structure,'{}'::jsonb),nullif(trim(p_model_label),''))
  returning id into v_id;

  insert into public.requirement_structuring_events(review_id,actor_id,event_type)
  values(v_id,auth.uid(),'created');
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'requirements.ai_review_created','requirement_structuring_review',v_id,jsonb_build_object('source_type',p_source_type));
  return v_id;
end $$;

create or replace function public.ops_update_requirement_suggestion(
  p_review_id uuid,
  p_suggested_structure jsonb,
  p_model_label text default null
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if jsonb_typeof(coalesce(p_suggested_structure,'{}'::jsonb)) <> 'object' then raise exception 'suggested structure must be an object'; end if;
  update public.requirement_structuring_reviews
     set suggested_structure=coalesce(p_suggested_structure,'{}'::jsonb), model_label=nullif(trim(p_model_label),''), updated_at=now()
   where id=p_review_id and status in ('draft','in_review');
  if not found then raise exception 'review not found or immutable'; end if;
  insert into public.requirement_structuring_events(review_id,actor_id,event_type)
  values(p_review_id,auth.uid(),'suggestion_updated');
end $$;

create or replace function public.ops_review_requirement_structure(
  p_review_id uuid,
  p_decision text,
  p_note text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare v_old text; v_new text; v_event text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_note is not null and char_length(p_note)>2000 then raise exception 'note too long'; end if;
  select status into v_old from public.requirement_structuring_reviews where id=p_review_id for update;
  if v_old is null then raise exception 'review not found'; end if;
  if p_decision not in ('start_review','approve','reject','note') then raise exception 'invalid decision'; end if;
  if p_decision='start_review' and v_old='draft' then v_new:='in_review'; v_event:='review_started';
  elsif p_decision='approve' and v_old in ('draft','in_review') then v_new:='approved'; v_event:='approved';
  elsif p_decision='reject' and v_old in ('draft','in_review') then v_new:='rejected'; v_event:='rejected';
  elsif p_decision='note' and v_old in ('draft','in_review') then v_new:=v_old; v_event:='note';
  else raise exception 'invalid review transition'; end if;

  update public.requirement_structuring_reviews set status=v_new, reviewer_id=auth.uid(), review_note=coalesce(nullif(trim(p_note),''),review_note), reviewed_at=case when v_new in ('approved','rejected') then now() else reviewed_at end, updated_at=now() where id=p_review_id;
  insert into public.requirement_structuring_events(review_id,actor_id,event_type,metadata)
  values(p_review_id,auth.uid(),v_event,jsonb_build_object('note_present',p_note is not null));
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'requirements.ai_review_transitioned','requirement_structuring_review',p_review_id,jsonb_build_object('from',v_old,'to',v_new));
end $$;

revoke all on function public.ops_create_requirement_structuring_review(text,uuid,text,jsonb,text) from public;
revoke all on function public.ops_update_requirement_suggestion(uuid,jsonb,text) from public;
revoke all on function public.ops_review_requirement_structure(uuid,text,text) from public;
grant execute on function public.ops_create_requirement_structuring_review(text,uuid,text,jsonb,text) to authenticated;
grant execute on function public.ops_update_requirement_suggestion(uuid,jsonb,text) to authenticated;
grant execute on function public.ops_review_requirement_structure(uuid,text,text) to authenticated;

comment on table public.requirement_structuring_reviews is 'Human-reviewed AI-assisted requirement structuring. Approval does not publish or mutate jobs/shifts, rates, eligibility, assignments, or client commitments.';
