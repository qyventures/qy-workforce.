-- Structural security checks for audited payroll adjustments.

do $$
begin
  if not exists (select 1 from pg_tables where schemaname='public' and tablename='payroll_adjustments' and rowsecurity) then
    raise exception 'payroll_adjustments must have RLS enabled';
  end if;

  if not exists (select 1 from pg_proc where proname='create_payroll_adjustment' and prosecdef) then
    raise exception 'create_payroll_adjustment must be security definer';
  end if;
  if not exists (select 1 from pg_proc where proname='review_payroll_adjustment' and prosecdef) then
    raise exception 'review_payroll_adjustment must be security definer';
  end if;
  if not exists (select 1 from pg_proc where proname='apply_payroll_adjustment' and prosecdef) then
    raise exception 'apply_payroll_adjustment must be security definer';
  end if;

  if has_table_privilege('authenticated','public.payroll_adjustments','INSERT')
     or has_table_privilege('authenticated','public.payroll_adjustments','UPDATE')
     or has_table_privilege('authenticated','public.payroll_adjustments','DELETE') then
    raise exception 'authenticated must not directly mutate payroll_adjustments';
  end if;

  if not has_function_privilege('authenticated','public.create_payroll_adjustment(uuid,text,numeric,text,uuid)','EXECUTE') then
    raise exception 'authenticated needs controlled adjustment RPC';
  end if;
end $$;

-- Guardrail text checks: separation of duties and exported-batch protection must remain explicit.
do $$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='review_payroll_adjustment' limit 1;
  if position('requester cannot review own adjustment' in src)=0 then raise exception 'missing requester/reviewer separation'; end if;

  select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='apply_payroll_adjustment' limit 1;
  if position('only draft payroll batches may be adjusted' in src)=0 then raise exception 'missing locked/exported batch protection'; end if;
end $$;
