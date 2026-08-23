# Payroll export RPC boundary

QY Workforce records payroll export evidence through `record_payroll_export(uuid,text,text,integer)`.

The supported RPC requires Finance/Admin authorization, a locked payroll batch, a SHA-256 checksum, and an item count matching the immutable batch membership. Re-recording is idempotent only when the export evidence is identical.

The earlier `mark_payroll_batch_exported(uuid)` RPC predates those controls. It remains in the migration history for compatibility with existing databases, but application roles no longer receive EXECUTE privilege on it. This prevents a caller from moving a payroll batch to `exported` without recording checksum/count evidence.

Application code and staging tests must use `record_payroll_export(...)` exclusively. No production payroll credentials or payment-provider credentials are required by this control.
