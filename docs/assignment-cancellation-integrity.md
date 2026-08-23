# Assignment cancellation integrity

Worker cancellation is part of shift-capacity control and must not be implemented as a free-form update to `shift_assignments.cancelled_at`.

`cancel_shift_assignment(uuid,text)` is the authoritative cancellation transition. It runs as a `SECURITY DEFINER` RPC with a fixed `search_path` and is executable only by authenticated users.

Workers may cancel only their own active assignment, only before the shift starts, and only before any attendance event has been recorded. Ops/Admin may cancel another worker's future assignment, but must provide a rationale. Rationale text is capped at 500 characters to avoid using audit metadata as a free-form data store.

The RPC acquires the same worker advisory lock used by secure shift acceptance. This serializes acceptance and cancellation decisions for a worker and prevents cancellation/acceptance races from producing inconsistent overlap or capacity outcomes.

Once attendance exists, cancellation is blocked. Operational corrections must preserve the assignment and use attendance/timesheet review flows instead of reopening headcount by cancelling evidence-backed work.

Every successful cancellation emits `shift_assignment.cancelled`, including the shift reference, whether it was worker self-service, and an optional bounded rationale. No identity document data, raw coordinates, or device fingerprints are copied into the audit event.

This control complements secure acceptance, accepted-shift term freezing, attendance validation, and approved-timesheet financial integrity. It does not use production identity or payroll credentials.
