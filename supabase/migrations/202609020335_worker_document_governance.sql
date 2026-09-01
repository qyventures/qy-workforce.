-- QY Workforce: privacy-safe worker document registry and review workflow.
-- Stores metadata/object keys only; raw files belong in a private bucket with signed access.

create table if not exists public.worker_documents (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete cascade,
  document_type text not null check (document_type in ('identity','work_eligibility','training','medical_certificate','qualification','other')),
  storage_object_key text not null,
  original_filename text,
  mime_type text,
  sha256 text,
  status text not null default 'submitted' check (status in ('submitted','under_review','approved','rejected','expired','retired')),
  issued_on date,
  expires_on date,
  review_note_redacted text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  retention_until timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(storage_object_key) between 1 and 500),
  check (storage_object_key !~* '^https?://'),
  check (original_filename is null or char_length(original_filename) <= 255),
  check (mime_type is null or char_length(mime_type) <= 120),
  check (sha256 is null or sha256 ~ '^[0-9a-fA-F]{64}$'),
  check (review_note_redacted is null or char_length(review_note_redacted) <= 2000),
  check (expires_on is null or issued_on is null or expires_on >= issued_on)
);

create index if not exists worker_documents_worker_status_idx
  on public.worker_documents(worker_id,status,document_type,expires_on);
create unique index if not exists worker_documents_object_key_idx
  on public.worker_documents(storage_object_key);

alter table public.worker_documents enable row level security;
revoke insert, update, delete on public.worker_documents from anon, authenticated;

create policy "workers read own document metadata"
  on public.worker_documents for select
  using (worker_id = auth.uid());

create policy "privileged read worker document metadata"
  on public.worker_documents for select
  using (public.is_privileged());

create or replace function public.register_worker_document(
  p_document_type text,
  p_storage_object_key text,
  p_original_filename text default null,
  p_mime_type text default null,
  p_sha256 text default null,
  p_issued_on date default null,
  p_expires_on date default null,
  p_retention_until timestamptz default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.worker_profiles where user_id=auth.uid()) then raise exception 'worker profile required'; end if;
  if p_document_type not in ('identity','work_eligibility','training','medical_certificate','qualification','other') then raise exception 'invalid document type'; end if;
  if p_storage_object_key is null or char_length(trim(p_storage_object_key)) not between 1 and 500 or p_storage_object_key ~* '^https?://' then raise exception 'invalid storage object key'; end if;
  if p_original_filename is not null and char_length(p_original_filename) > 255 then raise exception 'filename too long'; end if;
  if p_mime_type is not null and char_length(p_mime_type) > 120 then raise exception 'mime type too long'; end if;
  if p_sha256 is not null and p_sha256 !~ '^[0-9a-fA-F]{64}$' then raise exception 'invalid sha256'; end if;
  if p_expires_on is not null and p_issued_on is not null and p_expires_on < p_issued_on then raise exception 'invalid document dates'; end if;

  insert into public.worker_documents(worker_id,document_type,storage_object_key,original_filename,mime_type,sha256,issued_on,expires_on,retention_until)
  values(auth.uid(),p_document_type,trim(p_storage_object_key),nullif(trim(p_original_filename),''),nullif(trim(p_mime_type),''),lower(nullif(trim(p_sha256),'')),p_issued_on,p_expires_on,p_retention_until)
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_document.submitted','worker_document',v_id,jsonb_build_object('document_type',p_document_type,'has_expiry',p_expires_on is not null));
  return v_id;
end $$;

revoke all on function public.register_worker_document(text,text,text,text,text,date,date,timestamptz) from public;
grant execute on function public.register_worker_document(text,text,text,text,text,date,date,timestamptz) to authenticated;

create or replace function public.review_worker_document(
  p_document_id uuid,
  p_status text,
  p_review_note_redacted text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_doc public.worker_documents%rowtype;
begin
  if not public.is_ops() then raise exception 'ops role required'; end if;
  if p_status not in ('under_review','approved','rejected','expired') then raise exception 'invalid review status'; end if;
  if p_review_note_redacted is not null and char_length(p_review_note_redacted) > 2000 then raise exception 'review note too long'; end if;

  select * into v_doc from public.worker_documents where id=p_document_id for update;
  if not found then raise exception 'document not found'; end if;
  if v_doc.status='retired' then raise exception 'retired document is immutable'; end if;

  update public.worker_documents
     set status=p_status,
         review_note_redacted=nullif(trim(p_review_note_redacted),''),
         reviewed_by=auth.uid(),
         reviewed_at=now(),
         updated_at=now()
   where id=p_document_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_document.reviewed','worker_document',p_document_id,jsonb_build_object('from_status',v_doc.status,'to_status',p_status,'worker_id',v_doc.worker_id));
end $$;

revoke all on function public.review_worker_document(uuid,text,text) from public;
grant execute on function public.review_worker_document(uuid,text,text) to authenticated;

create or replace function public.retire_own_worker_document(p_document_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_status text;
begin
  select status into v_status from public.worker_documents where id=p_document_id and worker_id=auth.uid() for update;
  if not found then raise exception 'document not found'; end if;
  if v_status='approved' then raise exception 'approved document requires ops review before retirement'; end if;
  update public.worker_documents set status='retired',retired_at=now(),updated_at=now() where id=p_document_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_document.retired','worker_document',p_document_id,jsonb_build_object('previous_status',v_status));
end $$;

revoke all on function public.retire_own_worker_document(uuid) from public;
grant execute on function public.retire_own_worker_document(uuid) to authenticated;

comment on table public.worker_documents is
'Privacy-safe worker document metadata. Raw files must remain in private object storage and be accessed through short-lived signed URLs; public URLs are prohibited.';
