-- Structural regression checks for worker-document lifecycle evidence.

do $$
declare v_def text;
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_documents'::regclass
      and conname='worker_documents_review_evidence_consistency'
      and not convalidated
  ) then raise exception 'document review evidence constraint must be a NOT VALID forward-write constraint'; end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_documents'::regclass
      and conname='worker_documents_review_pair_consistency'
  ) then raise exception 'document reviewer and reviewed_at must be recorded as a pair'; end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_documents'::regclass
      and conname='worker_documents_retired_at_status_consistency'
  ) then raise exception 'retired_at must only exist for retired documents'; end if;

  select pg_get_functiondef('public.review_worker_document(uuid,text,text)'::regprocedure) into v_def;
  if position('for update' in lower(v_def)) = 0
     or position('only submitted or under-review documents may be reviewed' in lower(v_def)) = 0
     or position('reviewed_by=auth.uid()' in replace(lower(v_def),' ','')) = 0
     or position('reviewed_at=now()' in replace(lower(v_def),' ','')) = 0 then
    raise exception 'document review RPC must lock rows, enforce lifecycle and write reviewer evidence';
  end if;
end $$;

do $$
begin
  if has_function_privilege('anon','public.review_worker_document(uuid,text,text)','EXECUTE') then
    raise exception 'anonymous users must not review worker documents';
  end if;
  if has_table_privilege('authenticated','public.worker_documents','INSERT')
     or has_table_privilege('authenticated','public.worker_documents','UPDATE')
     or has_table_privilege('authenticated','public.worker_documents','DELETE') then
    raise exception 'worker documents must remain RPC-only';
  end if;
end $$;
