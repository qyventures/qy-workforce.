-- Structural safety checks for human-reviewed AI-assisted requirement structuring.

do $$
begin
  if not exists(select 1 from pg_class where relnamespace='public'::regnamespace and relname='requirement_structuring_reviews' and relrowsecurity) then
    raise exception 'requirement_structuring_reviews must have RLS enabled';
  end if;
  if not exists(select 1 from pg_class where relnamespace='public'::regnamespace and relname='requirement_structuring_events' and relrowsecurity) then
    raise exception 'requirement_structuring_events must have RLS enabled';
  end if;
  if has_table_privilege('authenticated','public.requirement_structuring_reviews','INSERT,UPDATE,DELETE') then
    raise exception 'authenticated direct writes to reviews must be denied';
  end if;
  if has_table_privilege('authenticated','public.requirement_structuring_events','INSERT,UPDATE,DELETE') then
    raise exception 'authenticated direct writes to events must be denied';
  end if;
  if has_function_privilege('anon','public.ops_create_requirement_structuring_review(text,uuid,text,jsonb,text)','EXECUTE') then
    raise exception 'anonymous create RPC execution must be denied';
  end if;
  if has_function_privilege('anon','public.ops_update_requirement_suggestion(uuid,jsonb,text)','EXECUTE') then
    raise exception 'anonymous suggestion RPC execution must be denied';
  end if;
  if has_function_privilege('anon','public.ops_review_requirement_structure(uuid,text,text)','EXECUTE') then
    raise exception 'anonymous review RPC execution must be denied';
  end if;
  if pg_get_functiondef('public.ops_create_requirement_structuring_review(text,uuid,text,jsonb,text)'::regprocedure) not ilike '%security definer%' then
    raise exception 'create RPC must be SECURITY DEFINER';
  end if;
  if pg_get_functiondef('public.ops_review_requirement_structure(uuid,text,text)'::regprocedure) not ilike '%public.is_ops()%' then
    raise exception 'review RPC must enforce Ops authorisation';
  end if;
  if pg_get_functiondef('public.ops_review_requirement_structure(uuid,text,text)'::regprocedure) ilike '%insert into public.shifts%'
     or pg_get_functiondef('public.ops_review_requirement_structure(uuid,text,text)'::regprocedure) ilike '%update public.shifts%'
     or pg_get_functiondef('public.ops_review_requirement_structure(uuid,text,text)'::regprocedure) ilike '%insert into public.shift_assignments%'
     or pg_get_functiondef('public.ops_review_requirement_structure(uuid,text,text)'::regprocedure) ilike '%update public.shift_assignments%' then
    raise exception 'AI review must not mutate shifts or assignments';
  end if;
end $$;
