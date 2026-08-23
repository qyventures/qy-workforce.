# Timesheet anomaly approval gate

Attendance anomaly detection remains deliberately non-blocking when a worker clocks in or out. Valid geofenced attendance is still captured so operational recovery and payroll review are possible even when heuristics flag a suspicious pattern.

Financial approval is stricter. `review_timesheet(...)` now checks high-severity anomalies for the timesheet's assignment before an approval transition:

- an **open** high-severity anomaly blocks approval until Ops reviews it;
- a **confirmed** high-severity anomaly blocks approval and requires the timesheet to be rejected/corrected rather than promoted to payroll;
- **dismissed** high-severity anomalies no longer block approval;
- low- and medium-severity anomalies remain advisory and do not automatically block payment;
- rejection remains available at all times, with the existing required rationale.

The gate is evaluated while the submitted timesheet row is locked, preserving the existing concurrency-safe review transition and separation-of-duties checks. Successful review events continue to be written to `audit_events`; approved events additionally record that the high-severity anomaly gate was evaluated.

This control intentionally does not copy device fingerprints, coordinates, worker identity evidence, or anomaly notes into timesheet audit metadata.
