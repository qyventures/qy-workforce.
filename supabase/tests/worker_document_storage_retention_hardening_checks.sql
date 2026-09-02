-- Regression checks for private worker-document keys and retention authority.
begin;
do $$
declare v_def text;
begin
  if not exists (select 1 from pg_constraint where conrelid='public.worker_documents'::regclass and conname='worker_documents_private_key_shape') then
    raise exception 'private storage key constraint missing';
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.worker_documents'::regclass and conname='worker_documents_retention_not_past') then
    raise exception 'retention timestamp constraint missing';
  end if;

  select pg_get_functiondef('public.register_worker_document(text,text,text,text,text,date,date,timestamptz)'::regprocedure) into v_def;
  if position('retention is assigned by operations' in lower(v_def))=0 then raise exception 'worker submission must not choose retention'; end if;
  if position('^workers/' in v_def)=0 or position('..' in v_def)=0 then raise exception 'document key must be worker-scoped and traversal-safe'; end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='set_worker_document_retention' and p.prosecdef
      and pg_get_functiondef(p.oid) ilike '%is_ops()%' and pg_get_functiondef(p.oid) ilike '%service_role%') then
    raise exception 'privileged retention RPC missing';
  end if;
  if has_table_privilege('authenticated','public.worker_documents','INSERT')
     or has_table_privilege('authenticated','public.worker_documents','UPDATE')
     or has_table_privilege('authenticated','public.worker_documents','DELETE') then
    raise exception 'worker documents must remain RPC-only';
  end if;
  if has_function_privilege('anon','public.set_worker_document_retention(uuid,timestamptz)','EXECUTE') then
    raise exception 'anonymous users must not assign retention';
  end if;
end $$;
rollback;
