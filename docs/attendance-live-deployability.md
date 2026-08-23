# Attendance live-deployability guard

Workers can accept a shift while fully deployable and later lose a prerequisite before the shift starts. Examples include expired residency/work-eligibility evidence, vetting status changes, expired training, role deactivation, suspension, or withdrawal/expiry of a required consent.

`202608231520_attendance_live_deployability_guard.sql` adds a database trigger on `time_events` that re-evaluates `worker_has_deployment_prerequisites(worker_id)` immediately before a `worker_app` clock-in is recorded.

The guard also binds the event creator to the worker on the active accepted assignment. This is defence in depth over `record_clock_event(...)`; future attendance entry points cannot accidentally bypass the same readiness boundary simply by inserting a worker-app clock-in row.

Clock-out is intentionally not subjected to the deployability test. If a qualification or consent expires after a valid clock-in, the worker must still be able to close attendance already performed so that worked time can be reviewed and paid. Existing geofence, location-accuracy, mocked-location, sequencing, timing-window and timesheet controls remain authoritative.

Identity verification, residency and work eligibility remain separate checks. The live predicate uses purpose-specific, expiry-aware residency and work-eligibility evidence and current consent-policy versions; this migration does not introduce or use production Singpass/MyInfo credentials.

Regression coverage is in `supabase/tests/attendance_live_deployability_guard_checks.sql`.
