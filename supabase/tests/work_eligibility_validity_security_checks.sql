-- Structural checks for time-bounded, independently reviewed work eligibility.
begin;

do $$
declare
  v_rpc text;
  v_prereq text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='worker_profiles'
      and column_name='eligibility_expires_at' and data_type='timestamp with time zone'
  ) then raise exception 'eligibility expiry column required'; end if;

  if to_regclass('public.work_eligibility_reviews') is null then
    raise exception 'work eligibility review history required';
  end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='work_eligibility_reviews' and c.relrowsecurity
  ) then raise exception 'work eligibility reviews must have RLS enabled'; end if;
  if has_table_privilege('authenticated','public.work_eligibility_reviews','INSERT')
     or has_table_privilege('authenticated','public.work_eligibility_reviews','UPDATE')
     or has_table_privilege('authenticated','public.work_eligibility_reviews','DELETE') then
    raise exception 'eligibility review history must not be directly mutable';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.work_eligibility_reviews'::regclass
      and tgname='work_eligibility_reviews_append_only' and not tgisinternal
  ) then raise exception 'eligibility review history requires an append-only trigger'; end if;

  if has_function_privilege('authenticated',
       'public.record_work_eligibility_staging(uuid,public.eligibility_status,text)','EXECUTE') then
    raise exception 'non-expiring eligibility RPC must be retired';
  end if;
  if not has_function_privilege('authenticated',
       'public.record_work_eligibility_staging(uuid,public.eligibility_status,text,timestamp with time zone,text)','EXECUTE')
     or has_function_privilege('anon',
       'public.record_work_eligibility_staging(uuid,public.eligibility_status,text,timestamp with time zone,text)','EXECUTE') then
    raise exception 'eligibility review RPC grants are unsafe';
  end if;

  select pg_get_functiondef(p.oid) into v_rpc
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='record_work_eligibility_staging'
    and pg_get_function_identity_arguments(p.oid) ilike '%timestamp with time zone%';
  if v_rpc is null
     or v_rpc not ilike '%self-review not permitted%'
     or v_rpc not ilike '%work eligibility consent required%'
     or v_rpc not ilike '%valid eligibility expiry required%'
     or v_rpc not ilike '%evidence reference required%'
     or v_rpc not ilike '%for update%'
     or v_rpc not ilike '%work_eligibility_reviews%'
     or v_rpc not ilike '%work_eligibility.recorded%' then
    raise exception 'eligibility RPC must lock, separate duties, validate validity/evidence and audit';
  end if;

  select pg_get_functiondef(p.oid) into v_prereq
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='worker_has_deployment_prerequisites';
  if v_prereq is null or v_prereq not ilike '%eligibility_expires_at > now()%' then
    raise exception 'deployability must reject expired eligibility';
  end if;
end;
$$;

rollback;
