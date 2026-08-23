-- Structural regression checks for payroll export RPC privilege boundary.
do $$
begin
  if has_function_privilege('anon', 'public.mark_payroll_batch_exported(uuid)', 'EXECUTE') then
    raise exception 'anon must not execute legacy payroll export transition';
  end if;
  if has_function_privilege('authenticated', 'public.mark_payroll_batch_exported(uuid)', 'EXECUTE') then
    raise exception 'authenticated must not execute legacy payroll export transition';
  end if;
  if has_function_privilege('public', 'public.mark_payroll_batch_exported(uuid)', 'EXECUTE') then
    raise exception 'PUBLIC must not execute legacy payroll export transition';
  end if;
  if not has_function_privilege('authenticated', 'public.record_payroll_export(uuid,text,text,integer)', 'EXECUTE') then
    raise exception 'authenticated Finance/Admin callers need supported export RPC execution';
  end if;
end $$;
