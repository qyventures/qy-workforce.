-- QY Workforce: tighten private document storage and retention authority.
-- Existing metadata is preserved; NOT VALID constraints protect new writes while
-- allowing a separate staging cleanup of any legacy rows.

alter table public.worker_documents
  add constraint worker_documents_private_key_shape
  check (
    storage_object_key !~ '(^|/)[.][.](/|$)'
    and storage_object_key !~ '^/'
    and storage_object_key !~ '^\\\\'
    and storage_object_key !~ '[[:cntrl:]]'
  ) not valid;

alter table public.worker_documents
  add constraint worker_documents_retention_not_past
  check (retention_until is null or retention_until >= created_at) not valid;

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
  if p_storage_object_key is null
     or char_length(trim(p_storage_object_key)) not between 1 and 500
     or p_storage_object_key ~* '^https?://'
     or p_storage_object_key !~ ('^workers/' || auth.uid()::text || '/')
     or p_storage_object_key ~ '(^|/)[.][.](/|$)'
     or p_storage_object_key ~ '^/'
     or p_storage_object_key ~ '^\\\\'
     or p_storage_object_key ~ '[[:cntrl:]]' then raise exception 'invalid private storage object key'; end if;
  if p_retention_until is not null then raise exception 'retention is assigned by operations'; end if;
  if p_original_filename is not null and char_length(p_original_filename) > 255 then raise exception 'filename too long'; end if;
  if p_mime_type is not null and char_length(p_mime_type) > 120 then raise exception 'mime type too long'; end if;
  if p_sha256 is not null and p_sha256 !~ '^[0-9a-fA-F]{64}$' then raise exception 'invalid sha256'; end if;
  if p_expires_on is not null and p_issued_on is not null and p_expires_on < p_issued_on then raise exception 'invalid document dates'; end if;

  insert into public.worker_documents(worker_id,document_type,storage_object_key,original_filename,mime_type,sha256,issued_on,expires_on)
  values(auth.uid(),p_document_type,trim(p_storage_object_key),nullif(trim(p_original_filename),''),nullif(trim(p_mime_type),''),lower(nullif(trim(p_sha256),'')),p_issued_on,p_expires_on)
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_document.submitted','worker_document',v_id,jsonb_build_object('document_type',p_document_type,'has_expiry',p_expires_on is not null));
  return v_id;
end $$;

revoke all on function public.register_worker_document(text,text,text,text,text,date,date,timestamptz) from public;
grant execute on function public.register_worker_document(text,text,text,text,text,date,date,timestamptz) to authenticated;

create or replace function public.set_worker_document_retention(
  p_document_id uuid,
  p_retention_until timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_worker uuid; v_created_at timestamptz;
begin
  if not (public.is_ops() or coalesce(auth.role() = 'service_role', false)) then raise exception 'ops or service role required'; end if;
  if p_retention_until is null then raise exception 'retention timestamp required'; end if;
  select worker_id, created_at into v_worker, v_created_at from public.worker_documents where id=p_document_id for update;
  if not found then raise exception 'document not found'; end if;
  if p_retention_until < v_created_at then raise exception 'retention timestamp precedes document creation'; end if;
  update public.worker_documents set retention_until=p_retention_until,updated_at=now() where id=p_document_id;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_document.retention_set','worker_document',p_document_id,jsonb_build_object('worker_id',v_worker,'retention_until',p_retention_until));
end $$;

revoke all on function public.set_worker_document_retention(uuid,timestamptz) from public;
grant execute on function public.set_worker_document_retention(uuid,timestamptz) to authenticated, service_role;

comment on function public.set_worker_document_retention(uuid,timestamptz) is
'Ops/Admin or service-role-only retention assignment. Workers cannot extend or shorten document retention through submission.';
