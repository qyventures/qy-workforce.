# Audit data minimisation

QY Workforce audit events are intended to prove who performed a privileged action, what entity was affected, when it happened, and the non-sensitive outcome of that action. They are not an evidence store.

Migration `0028_audit_metadata_minimisation.sql` adds a database-enforced guard on `audit_events.metadata`. The guard recursively rejects raw/highly sensitive identity and authentication fields, including NRIC/FIN/passport or work-pass numbers, raw Singpass/MyInfo payloads, verified-attribute blobs, and authentication tokens. Nested objects and arrays are checked as well.

Safe references remain permitted. Use worker/entity UUIDs, decision/status values, timestamps, reason codes, provider names and cryptographic hashes such as `provider_subject_hash` where a correlation reference is required. Do not place source documents, raw provider responses, bearer credentials, or direct identity document numbers into audit metadata.

This control complements the separate identity, residency and work-eligibility evidence tables. Those lifecycles remain independent; audit records should reference their decisions rather than duplicate their evidence.

The regression file `supabase/tests/audit_metadata_minimisation_checks.sql` verifies safe metadata, nested/array detection and the actual trigger boundary. Run it only against disposable local/test or staging databases, never production credentials.
