-- QY Workforce: retire legacy payroll export transition that predates export evidence.
-- The supported record_payroll_export(...) RPC records immutable export evidence.

revoke all on function public.mark_payroll_batch_exported(uuid) from public;
revoke all on function public.mark_payroll_batch_exported(uuid) from anon;
revoke all on function public.mark_payroll_batch_exported(uuid) from authenticated;

comment on function public.mark_payroll_batch_exported(uuid) is
  'Deprecated legacy payroll export transition. Application execution is revoked; use record_payroll_export(uuid,text,text,integer) with export evidence.';

revoke all on function public.record_payroll_export(uuid,text,text,integer) from public;
revoke all on function public.record_payroll_export(uuid,text,text,integer) from anon;
grant execute on function public.record_payroll_export(uuid,text,text,integer) to authenticated;
