# Attendance anomaly review

QY Workforce treats the server-side `record_clock_event` RPC as authoritative for accepting attendance. It validates assignment ownership, geofence configuration, location accuracy, mocked-location signals, event sequencing and the permitted shift window before writing a `time_events` record.

Migration `0027_attendance_anomaly_review.sql` adds a second, non-blocking review layer for events that passed those controls but still merit operational scrutiny. This avoids turning weak fraud signals into automatic worker rejection.

## Signals

The detector currently queues four bounded signals:

- **device reuse (high):** the same device fingerprint hash appears for different workers inside a 12-hour window;
- **low location confidence (medium):** accepted location accuracy is above 50m but still within the RPC's hard 100m limit;
- **edge of geofence (low):** an accepted event is in the outer 20% of the configured site radius;
- **unusual shift window (medium):** clock-in is more than 45 minutes early or clock-out is more than two hours after scheduled end while still inside the RPC's broader recovery window.

The anomaly record deliberately does **not** copy raw latitude, longitude or device fingerprint values. Those remain in the restricted source attendance record only. Metadata stores coarse bands/reasons needed for review.

## Access and review

`attendance_anomalies` has RLS enabled. Privileged users may read it; workers receive no anomaly read policy. Direct authenticated insert/update/delete is revoked. Creation is trigger-owned and disposition is only through `review_attendance_anomaly`.

Only Ops/Admin roles may dismiss or confirm an anomaly. Review notes are explicitly redacted free text and capped at 500 characters. Both anomaly creation and review disposition create audit events.

A confirmed anomaly does not automatically change payroll, worker status or assignment state. Any consequential action must use the existing audited workflows and appropriate human review. This separation prevents a heuristic signal from silently becoming an adverse employment/payment decision.

## Privacy and retention

The queue is intended for targeted fraud/attendance review and follows the same minimisation principle as other workforce records. Do not place NRIC, passport numbers, exact device identifiers, raw provider payloads, or unnecessary worker personal data in review notes.

Retention enforcement should purge anomaly records with their source attendance data or according to the configured attendance retention policy. Because `event_id` and `assignment_id` use cascading foreign keys, deletion of the underlying attendance/assignment lifecycle removes dependent anomaly records.

## Testing

`supabase/tests/attendance_anomaly_security_checks.sql` asserts RLS, privileged review, audit coverage, bounded notes, device-reuse/geofence signals, and the absence of worker-facing anomaly policies.
