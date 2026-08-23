-- Regression checks: legacy payroll export transition must not remain executable
-- by application roles after evidence-bearing export recording is introduced.

do $$
begin
  if has_function_privilege('authenticated', 'public.mark_payroll_batch_exported(uuid)', 'EXECUTE') then
    raise exception 'authenticated must not execute legacy mark_payroll_batch_exported(uuid)';
  end if;

  if has_function_privilege('anon', 'public.mark_payroll_batch_exported(uuid)', 'EXECUTE') then
    raise exception 'anon must not execute legacy mark_payroll_batch_exported(uuid)';
  end if;

  if not has_function_privilege('authenticated', 'public.record_payroll_export(uuid,text,text,integer)', 'EXECUTE') then
    raise exception 'authenticated must retain access to evidence-bearing record_payroll_export RPC';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'record_payroll_export'
      and pg_get_function_identity_arguments(p.oid) = 'p_batch uuid, p_format text, p_checksum text, p_count integer'
      and p.prosecdef
      and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
  ) then
    raise exception 'record_payroll_export must remain SECURITY DEFINER with search_path=public';
  end if;
end;
$$;
