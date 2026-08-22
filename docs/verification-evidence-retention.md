# Verification evidence retention

QY Workforce keeps identity verification, residency verification and work eligibility as separate purposes and separate evidence lifecycles. Production Singpass/MyInfo integration remains disabled; the current provider boundary accepts mock/staging/manual-review evidence only.

## What is retained

After the configured retention window, `run_verification_evidence_retention` removes only the purpose-specific `evidence_hash` from historical `residency_verifications` and `work_eligibility_checks` rows. The decision/outcome, source, environment, check timestamps and validity window remain available for operational history, dispute handling and audit.

The migration deliberately does not collapse residency or work eligibility back into the identity-verification record. Current deployability continues to use the latest non-expired purpose-specific decision.

## Retention holds

Workers with a privacy request carrying `retention_hold=true` are excluded from evidence minimisation until the hold is removed. This matches the existing location/identity retention design and prevents automated cleanup from destroying evidence that is under legal or dispute review.

## Roles and execution

- Admin and service-role callers may execute minimisation.
- Admin, Auditor and service-role callers may preview counts.
- Ordinary authenticated workers cannot execute destructive maintenance even though the RPC is exposed to the authenticated database role; the function performs the application-role check internally.
- Every preview/execution creates a `retention_runs` record and an `audit_events` entry.
- Runs are batch-capped at 5,000 records per evidence class.

## Policy defaults

The two new retention classes inherit the current `identity_verifications` retention period when first installed (730 days in the current baseline). Administrators may later change each class independently through the retention-policy table, so residency and work-eligibility evidence do not have to share a policy forever.

## Operational sequence

1. Run `run_verification_evidence_retention(false, <limit>)` to preview eligible rows.
2. Confirm there are no unexpected retention holds or policy settings.
3. Run `run_verification_evidence_retention(true, <limit>)` from an Admin/service-role maintenance context.
4. Review the corresponding `retention_runs` and `retention.verification_evidence_executed` audit event.

Do not place raw Singpass/MyInfo payloads, NRIC/FIN/passport values or other direct identity documents into `evidence_hash`, audit metadata or these evidence tables. Evidence references should remain one-way/non-reversible hashes or external controlled references only.
