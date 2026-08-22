# Identity, Residency and Work-Eligibility Boundaries

QY Workforce treats identity proof, residency and legal work eligibility as three independent controls. Passing one must never imply either of the others.

## Identity

`identity_provider_sessions` is the provider-session abstraction. V1 accepts only `mock` and `singpass_myinfo` providers in `mock` or `staging` environments. Raw Singpass/MyInfo payloads, access tokens and NRIC values must not be stored in the workforce database. Persist only normalized decisions and irreversible provider/evidence hashes.

`complete_identity_verification_staging` now updates identity state only. Its historical residency/work-eligibility parameters remain in the signature for compatibility, but non-default values are rejected so callers cannot couple the decisions again.

## Residency

`residency_verifications` records a purpose-specific decision, category, source, evidence hash and optional validity end. Writes are RPC-only through `record_residency_verification_staging`; workers may read only their own records through RLS. A failed/manual-review/latest-expired record makes current residency false once this evidence lifecycle has been adopted for that worker.

## Work eligibility

`work_eligibility_checks` independently records `eligible`, `ineligible` or `manual_review`, source, evidence hash and optional expiry. Writes are RPC-only through `record_work_eligibility_staging`. The denormalized `worker_profiles.work_eligibility` field is the current summary, not the evidence record.

## Deployability

`worker_has_deployment_prerequisites` evaluates identity, current residency and current work eligibility separately, in addition to approved active role, vetting, current mandatory training and required consents. `worker_is_deployable` still additionally requires the Ops-controlled profile status to be `deployable`.

For backward compatibility, workers with no purpose-specific residency or eligibility evidence continue to use the existing profile summary. Once the first purpose-specific evidence row exists, the latest row and its expiry become authoritative. This permits gradual migration without silently disabling the existing workforce.

## Provider safety

Production identity verification is deliberately not implemented in these database RPCs. The only allowed environments are `mock` and `staging`. A future production Singpass/MyInfo adapter should terminate OAuth/OIDC outside Postgres, validate state/nonce/PKCE and provider signatures there, then send only normalized outcomes across a trusted service boundary.

Do not place production secrets, client secrets, access tokens or raw MyInfo responses in migrations, SQL tests, logs or audit metadata.

## Tests

Run `supabase/tests/verification_separation_checks.sql` after migrations in a disposable local/staging database. It asserts RLS, direct-write revocation, RPC security-definer boundaries and the mock/staging environment constraints.
