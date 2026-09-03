-- QY Workforce: make worker-document review and retirement evidence consistent.
-- NOT VALID keeps legacy staging rows deployable while protecting all new writes.

alter table public.worker_documents
  drop constraint if exists worker_documents_review_evidence_consistency;
alter table public.worker_documents
  add constraint worker_documents_review_evidence_consistency
  check (
    (status = 'submitted' and reviewed_by is null and reviewed_at is null and retired_at is null)
    or (status in ('under_review','approved','rejected','expired')
        and reviewed_by is not null and reviewed_at is not null and retired_at is null)
    or (status = 'retired' and retired_at is not null)
  ) not valid;

alter table public.worker_documents
  drop constraint if exists worker_documents_review_pair_consistency;
alter table public.worker_documents
  add constraint worker_documents_review_pair_consistency
  check ((reviewed_by is null) = (reviewed_at is null)) not valid;

alter table public.worker_documents
  drop constraint if exists worker_documents_retired_at_status_consistency;
alter table public.worker_documents
  add constraint worker_documents_retired_at_status_consistency
  check (retired_at is null or status = 'retired') not valid;

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
  if v_doc.status not in ('submitted','under_review') then
    raise exception 'only submitted or under-review documents may be reviewed';
  end if;

  update public.worker_documents
     set status=p_status,
         review_note_redacted=nullif(trim(p_review_note_redacted),''),
         reviewed_by=auth.uid(),
         reviewed_at=now(),
         updated_at=now()
   where id=p_document_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_document.reviewed','worker_document',p_document_id,
         jsonb_build_object('from_status',v_doc.status,'to_status',p_status,'worker_id',v_doc.worker_id));
end $$;

revoke all on function public.review_worker_document(uuid,text,text) from public;
grant execute on function public.review_worker_document(uuid,text,text) to authenticated;

comment on table public.worker_documents is
'Privacy-safe worker document metadata. Submitted documents have no review evidence; reviewed documents require reviewer evidence; retired documents require retirement evidence. Raw files must remain in private object storage and be accessed through short-lived signed URLs.';
