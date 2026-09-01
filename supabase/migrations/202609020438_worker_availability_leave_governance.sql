-- QY Workforce: worker availability, leave and exception governance.
-- Worker-entered records are self-service, review is server-authoritative, and all state changes are audited.

create table if not exists public.worker_availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  exception_type text not null check (exception_type in ('unavailable','leave','medical_leave','training','other')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','cancelled')),
  reason_redacted text,
  supporting_document_id uuid references public.worker_documents(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note_redacted text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (reason_redacted is null or char_length(reason_redacted) <= 1000),
  check (review_note_redacted is null or char_length(review_note_redacted) <= 2000)
);

create index if not exists worker_availability_exceptions_worker_time_idx
  on public.worker_availability_exceptions(worker_id,starts_at,ends_at,status);

alter table public.worker_availability_exceptions enable row level security;
revoke insert, update, delete on public.worker_availability_exceptions from anon, authenticated;

create policy "workers read own availability exceptions"
  on public.worker_availability_exceptions for select
  using (worker_id = auth.uid());

create policy "privileged read availability exceptions"
  on public.worker_availability_exceptions for select
  using (public.is_privileged());

create or replace function public.submit_worker_availability_exception(
  p_exception_type text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason_redacted text default null,
  p_supporting_document_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_doc_worker uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then raise exception 'worker profile required'; end if;
  if p_exception_type not in ('unavailable','leave','medical_leave','training','other') then raise exception 'invalid exception type'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then raise exception 'invalid time range'; end if;
  if p_reason_redacted is not null and char_length(p_reason_redacted) > 1000 then raise exception 'reason too long'; end if;

  if p_supporting_document_id is not null then
    select worker_id into v_doc_worker from public.worker_documents where id=p_supporting_document_id;
    if not found or v_doc_worker <> auth.uid() then raise exception 'supporting document not owned by worker'; end if;
  end if;

  insert into public.worker_availability_exceptions(worker_id,exception_type,starts_at,ends_at,reason_redacted,supporting_document_id)
  values(auth.uid(),p_exception_type,p_starts_at,p_ends_at,nullif(trim(p_reason_redacted),''),p_supporting_document_id)
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_availability_exception.submitted','worker_availability_exception',v_id,
         jsonb_build_object('exception_type',p_exception_type,'starts_at',p_starts_at,'ends_at',p_ends_at,'has_supporting_document',p_supporting_document_id is not null));
  return v_id;
end $$;

revoke all on function public.submit_worker_availability_exception(text,timestamptz,timestamptz,text,uuid) from public;
grant execute on function public.submit_worker_availability_exception(text,timestamptz,timestamptz,text,uuid) to authenticated;

create or replace function public.review_worker_availability_exception(
  p_exception_id uuid,
  p_status text,
  p_review_note_redacted text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.worker_availability_exceptions%rowtype;
begin
  if not public.is_ops() then raise exception 'ops role required'; end if;
  if p_status not in ('approved','rejected') then raise exception 'invalid review status'; end if;
  if p_review_note_redacted is not null and char_length(p_review_note_redacted) > 2000 then raise exception 'review note too long'; end if;

  select * into v_row from public.worker_availability_exceptions where id=p_exception_id for update;
  if not found then raise exception 'exception not found'; end if;
  if v_row.status <> 'submitted' then raise exception 'only submitted records may be reviewed'; end if;
  if v_row.worker_id = auth.uid() then raise exception 'requester cannot review own exception'; end if;

  update public.worker_availability_exceptions
     set status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),review_note_redacted=nullif(trim(p_review_note_redacted),''),updated_at=now()
   where id=p_exception_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_availability_exception.reviewed','worker_availability_exception',p_exception_id,
         jsonb_build_object('worker_id',v_row.worker_id,'from_status',v_row.status,'to_status',p_status));
end $$;

revoke all on function public.review_worker_availability_exception(uuid,text,text) from public;
grant execute on function public.review_worker_availability_exception(uuid,text,text) to authenticated;

create or replace function public.cancel_own_worker_availability_exception(p_exception_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.worker_availability_exceptions%rowtype;
begin
  select * into v_row from public.worker_availability_exceptions
   where id=p_exception_id and worker_id=auth.uid() for update;
  if not found then raise exception 'exception not found'; end if;
  if v_row.status not in ('submitted','approved') then raise exception 'record cannot be cancelled'; end if;
  if v_row.ends_at <= now() then raise exception 'past exception cannot be cancelled'; end if;

  update public.worker_availability_exceptions
     set status='cancelled',cancelled_at=now(),updated_at=now()
   where id=p_exception_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_availability_exception.cancelled','worker_availability_exception',p_exception_id,
         jsonb_build_object('previous_status',v_row.status,'exception_type',v_row.exception_type));
end $$;

revoke all on function public.cancel_own_worker_availability_exception(uuid) from public;
grant execute on function public.cancel_own_worker_availability_exception(uuid) to authenticated;

comment on table public.worker_availability_exceptions is
'Worker availability, leave, medical leave and other exception records. Supporting documents reference private worker document metadata; no raw medical content is stored here.';
