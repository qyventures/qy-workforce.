# QY Workforce Security & PDPA Baseline

This document defines non-negotiable launch controls for QY Workforce.

## Privacy / PDPA

- Maintain a personal-data inventory and data-flow map.
- Collect only attributes required for workforce onboarding and operations.
- Record purpose, notice/consent where applicable, source and verification timestamp.
- Keep identity verification separate from work-eligibility decisions.
- Provide workflows for access/correction and retention/deletion.
- Do not retain Singpass tokens or raw identity payloads longer than operationally required.
- Keep worker-requested identity scopes to the minimum contract; configure any provider-specific attribute retrieval only in the protected staging bridge.
- Avoid NRIC/full identifier display except where strictly necessary and authorised.
- Define overseas-transfer controls before using any non-Singapore processor for personal data.
- Maintain breach-response and notification procedures.

## Authentication / authorisation

- MFA required for privileged Ops/Admin users before production.
- RBAC roles: worker, supervisor, recruiter, ops_manager, finance, admin, auditor.
- Supabase Row Level Security enabled on every personal/operational table.
- Least-privilege service accounts; no shared admin accounts.
- Short-lived user sessions and controlled refresh tokens.
- Re-authentication required for high-risk actions.

## Application security

- TLS only in staging/production.
- CSP and secure HTTP headers.
- CSRF protection where cookie-based state changes are used.
- Strict server-side input validation.
- Rate limits on login, identity callbacks, clock-in/out and administrative mutation endpoints.
- No secrets or personal data in application logs.
- Tamper-evident audit records for identity, eligibility, assignment, time and payroll changes.
- GPS values collected only for shift attendance purposes and with defined retention.

## Secrets / cryptography

- No credentials or private keys in Git.
- Separate keys/secrets for dev, staging and production.
- Key rotation procedure documented before production.
- Encryption at rest for sensitive data and encrypted transport for all external integrations.
- Singpass signing/encryption keys stored only in a secrets manager or protected host environment.

## Software supply chain

- Lockfiles committed.
- Dependency scanning in CI.
- Secret scanning in CI.
- SAST in CI.
- SBOM generated for release candidates.
- Critical/high vulnerabilities must be remediated or explicitly risk-accepted before launch.

## Infrastructure

- Dev/staging/prod separation.
- Database backups and tested restore procedure.
- Restricted production database access.
- Security monitoring/alerting for unusual login, privilege and API activity.
- Patch/update policy for OS, runtime and dependencies.

## Pen-test launch gate

Before production launch:

1. Threat model completed and reviewed.
2. DAST run against staging.
3. Independent penetration test conducted.
4. Critical/high findings fixed and re-tested.
5. PDPA/privacy review completed.
6. Singpass production configuration validated.
7. Backup/restore and incident-response exercises completed.
8. Security sign-off recorded.
