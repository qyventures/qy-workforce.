-- Structural regression checks for the labour requisition workflow.

do $$
begin
  if to_regclass('public.labour_requisitions') is null then
    raise exception 'labour_requisitions table missing';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='labour_requisitions' and c.relrowsecurity
  ) then
    raise exception 'RLS must be enabled on labour_requisitions';
  end if;

  if has_table_privilege('authenticated','public.labour_requisitions','INSERT')
     or has_table_privilege('authenticated','public.labour_requisitions','UPDATE')
     or has_table_privilege('authenticated','public.labour_requisitions','DELETE') then
    raise exception 'authenticated must not mutate labour_requisitions directly';
  end if;

  if has_table_privilege('anon','public.labour_requisitions','INSERT')
     or has_table_privilege('anon','public.labour_requisitions','UPDATE')
     or has_table_privilege('anon','public.labour_requisitions','DELETE') then
    raise exception 'anon must not mutate labour_requisitions directly';
  end if;

  if not has_function_privilege('authenticated',
    'public.create_labour_requisition(uuid,uuid,integer,timestamptz,timestamptz,numeric,numeric,text)', 'EXECUTE') then
    raise exception 'authenticated create requisition RPC grant missing';
  end if;

  if not has_function_privilege('authenticated',
    'public.review_labour_requisition(uuid,text,text)', 'EXECUTE') then
    raise exception 'authenticated review requisition RPC grant missing';
  end if;

  if has_function_privilege('anon',
    'public.create_labour_requisition(uuid,uuid,integer,timestamptz,timestamptz,numeric,numeric,text)', 'EXECUTE') then
    raise exception 'anon must not execute create requisition RPC';
  end if;

  if has_function_privilege('anon',
    'public.review_labour_requisition(uuid,text,text)', 'EXECUTE') then
    raise exception 'anon must not execute review requisition RPC';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='create_labour_requisition'
      and p.prosecdef and p.proconfig @> array['search_path=public']
  ) then
    raise exception 'create requisition RPC must be SECURITY DEFINER with fixed search_path';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_labour_requisition'
      and p.prosecdef and p.proconfig @> array['search_path=public']
  ) then
    raise exception 'review requisition RPC must be SECURITY DEFINER with fixed search_path';
  end if;
end;
$$;
