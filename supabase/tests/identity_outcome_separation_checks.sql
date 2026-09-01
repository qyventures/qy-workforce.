-- Identity, residency and eligibility must remain separate, audited boundaries.
begin;

do $$
declare
  v_identity text;
  v_residency text;
  v_eligibility text;
begin
  select pg_get_functiondef(p.oid) into v_identity
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='complete_identity_verification_staging';

  if v_identity is null
     or v_identity not ilike '%status=''callback_received''%'
     or v_identity not ilike '%residency and work eligibility require separate verification%'
     or v_identity not ilike '%valid provider subject hash required%' then
    raise exception 'identity completion must require callback, hashed subject and separate outcomes';
  end if;

  select pg_get_functiondef(p.oid) into v_residency
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='record_residency_verification_staging';
  if v_residency is null
     or v_residency not ilike '%residency category required%'
     or v_residency not ilike '%residency_verification.recorded%' then
    raise exception 'residency verification must validate and audit independently';
  end if;

  select pg_get_functiondef(p.oid) into v_eligibility
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='record_work_eligibility_staging';
  if v_eligibility is null
     or v_eligibility not ilike '%purpose=''work_eligibility''%'
     or v_eligibility not ilike '%work eligibility consent required%'
     or v_eligibility not ilike '%work_eligibility.recorded%' then
    raise exception 'work eligibility must require consent and audit independently';
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('complete_identity_verification_staging',
                        'record_residency_verification_staging',
                        'record_work_eligibility_staging')
      and not p.prosecdef
  ) then
    raise exception 'verification outcome RPCs must remain security-definer boundaries';
  end if;

  if not has_function_privilege('authenticated',
       'public.record_residency_verification_staging(uuid,boolean,text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated',
       'public.record_work_eligibility_staging(uuid,public.eligibility_status,text)', 'EXECUTE') then
    raise exception 'authenticated ops callers require explicit outcome RPC grants';
  end if;

  if has_function_privilege('anon',
       'public.record_residency_verification_staging(uuid,boolean,text,text)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.record_work_eligibility_staging(uuid,public.eligibility_status,text)', 'EXECUTE') then
    raise exception 'anonymous callers must not execute verification outcome RPCs';
  end if;
end $$;

rollback;
