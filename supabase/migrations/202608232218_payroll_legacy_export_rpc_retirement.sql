-- QY Workforce: retire legacy payroll export transition that predates export evidence.
--
-- Migration 0022 introduced record_payroll_export(batch, format, checksum, count),
-- which verifies locked batch membership and requires immutable SHA-256/count
-- evidence. The older mark_payroll_batch_exported(batch) function from 0005
-- lacks those controls. Keeping it executable would allow privileged app users
-- to bypass the stronger export-integrity boundary.

revoke all on function public.mark_payroll_batch_exported(uuid) from public;
revoke all on function public.mark_payroll_batch_exported(uuid) from anon;
revoke all on function public.mark_payroll_batch_exported(uuid) from authenticated;

comment on function public.mark_payroll_batch_exported(uuid) is
  'Deprecated legacy payroll export transition. Application execution is revoked; use record_payroll_export(uuid,text,text,integer) with immutable export evidence.';

-- Explicitly preserve the supported RPC boundary for authenticated Finance/Admin
-- callers; record_payroll_export performs its own current_app_role() check.
revoke all on function public.record_payroll_export(uuid,text,text,integer) from public;
grant execute on function public.record_payroll_export(uuid,text,text,integer) to authenticated;
