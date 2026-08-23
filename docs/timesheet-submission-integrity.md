# Timesheet submission integrity

Worker timesheet submission is an audited server-side transition. Clients cannot write `timesheets` directly.

## State rules

- `draft` and `rejected` timesheets may be submitted by the assigned worker.
- A repeated submission while already `submitted` is idempotent and returns the existing timesheet ID.
- `approved` and `payroll_ready` are terminal to worker submission. A worker retry cannot clear supervisor approval or payroll readiness.
- Assignment and existing timesheet rows are locked during submission to serialize cancellation, retry, review and payroll races.

## Attendance basis

Payable time is derived only from attendance records that:

- belong to the assignment;
- were accepted by the authoritative geofence check (`within_geofence = true`);
- came from the `worker_app` source; and
- were created by the assigned worker.

A complete trusted clock-in/clock-out pair is required. Durations over 24 hours are rejected for manual review rather than silently creating payable time.

## Financial basis

Worker and client amounts are recalculated from the shift rates and trusted attendance minutes when a draft/rejected timesheet is submitted. Separate approved-timesheet integrity controls freeze the financial basis after approval.

## Audit

A successful transition to `submitted` records `timesheet.submitted` with the assignment ID and payable minutes. No identity document, raw location, device fingerprint or provider payload is copied into audit metadata.
