-- Structural regression checks for reusable job templates and shift operational details.

do $$
begin
  if to_regclass('public.job_templates') is null then raise exception 'job_templates missing'; end if;
  if to_regclass('public.shift_operational_details') is null then raise exception 'shift_operational_details missing'; end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='job_templates' and c.relrowsecurity
  ) then raise exception 'RLS must be enabled on job_templates'; end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='shift_operational_details' and c.relrowsecurity
  ) then raise exception 'RLS must be enabled on shift_operational_details'; end if;

  if has_table_privilege('authenticated','public.job_templates','INSERT')
     or has_table_privilege('authenticated','public.job_templates','UPDATE')
     or has_table_privilege('authenticated','public.job_templates','DELETE') then
    raise exception 'authenticated must not mutate job_templates directly';
  end if;
  if has_table_privilege('authenticated','public.shift_operational_details','INSERT')
     or has_table_privilege('authenticated','public.shift_operational_details','UPDATE')
     or has_table_privilege('authenticated','public.shift_operational_details','DELETE') then
    raise exception 'authenticated must not mutate shift_operational_details directly';
  end if;

  if not has_function_privilege('authenticated','public.create_job_template(uuid,text,uuid,uuid,text,text,text,text,text,integer,numeric,numeric,boolean,text)','EXECUTE') then
    raise exception 'create_job_template grant missing';
  end if;
  if not has_function_privilege('authenticated','public.create_shift_from_template(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric,boolean,boolean)','EXECUTE') then
    raise exception 'create_shift_from_template grant missing';
  end if;
  if has_function_privilege('anon','public.create_job_template(uuid,text,uuid,uuid,text,text,text,text,text,integer,numeric,numeric,boolean,text)','EXECUTE')
     or has_function_privilege('anon','public.create_shift_from_template(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric,boolean,boolean)','EXECUTE') then
    raise exception 'anon must not execute job template RPCs';
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname in ('create_job_template','create_shift_from_template')
        and p.prosecdef and p.proconfig @> array['search_path=public']) <> 2 then
    raise exception 'job template RPCs must be SECURITY DEFINER with fixed search_path';
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='job_templates' and policyname='privileged read job templates') then
    raise exception 'job template privileged read policy missing';
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='shift_operational_details' and policyname='privileged read shift operational details') then
    raise exception 'shift operational details privileged read policy missing';
  end if;
end;
$$;
