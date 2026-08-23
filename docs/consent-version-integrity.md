# Consent version integrity

QY Workforce treats consent as a versioned operational prerequisite rather than a mutable worker-profile flag.

## Security boundary

Workers no longer insert, update, or delete `worker_consents` rows directly. Consent changes pass through `grant_worker_consent(...)` and `withdraw_worker_consent(...)`, which derive the worker from `auth.uid()`, use server timestamps, fix the source to `worker_app`, and emit audit events.

`consent_policy_versions` maintains the current effective policy version per purpose. A worker may only grant the current effective version. When a new grant is recorded, any older active grant for that purpose is closed first.

Withdrawal immediately closes all active grants for the purpose and records an append-only negative consent event. This makes withdrawal effective for deployability without erasing the historical record.

## Deployability

The authoritative `worker_has_deployment_prerequisites(...)` predicate now requires current-version consent for:

- identity verification;
- work eligibility processing; and
- location clocking.

A stale historical consent is therefore insufficient for shift discovery or acceptance once a newer policy version becomes current.

Communications and analytics remain optional and do not affect deployability.

## Migration behaviour

During migration, each purpose is bootstrapped from the most recently recorded existing policy version so already-valid workers are not needlessly invalidated. Purposes with no existing consent history receive `v1` as the initial current version.

Policy publication should be handled by a privileged administrative workflow. Production identity-provider credentials are not required or introduced by this change.

## Tests

`supabase/tests/consent_version_integrity_checks.sql` verifies that:

- only one current policy version may exist per purpose;
- authenticated users cannot write `worker_consents` directly;
- consent RPCs are the authenticated write boundary;
- SECURITY DEFINER functions pin `search_path`;
- deployability is bound to current-version required consent; and
- grant/withdraw flows retain server-owned timestamps and audit events.
