# QY Workforce security readiness

This checklist tracks staging and production hardening for the worker mobile app, public website, Ops/Admin surfaces and Supabase backend.

## PDPA data inventory and flows

- Worker identity facts are separated into identity verification, residency and work eligibility.
- Mobile and web clients should collect only data needed for onboarding, staffing, attendance, timesheets and support.
- Worker identity data must not be exposed in client/site margin reporting or broad Ops dashboards when pseudonymous operational labels are sufficient.
- Consent, policy version and audit events must be retained for identity/location/workflow actions.
- Raw Singpass/MyInfo tokens, refresh tokens, ID tokens and raw provider payloads must not be persisted in application tables or logs.
- Retention/deletion periods must remain registry-driven and reviewed before production launch.

## Authorization and database controls

- RLS must remain enabled on worker, identity, client, site, role, shift, assignment, attendance and timesheet surfaces.
- Authenticated clients must not directly mutate authoritative attendance, timesheet, payroll, shift-demand or eligibility state.
- SECURITY DEFINER RPCs must perform explicit role/site/ownership checks and use a restricted search_path.
- Supervisor approval must be site-scoped, auditable, row-locked and prohibit self-review.
- Finance/Admin boundaries must remain separate from worker/supervisor capabilities for payroll batching/export.

## Abuse, replay and concurrency

- OTP endpoints require provider-side rate limiting and abuse monitoring before production.
- Shift acceptance, attendance events, identity callbacks, timesheet reviews and payroll transitions require idempotency/concurrency protection.
- Identity state/nonce hashes must be single-use and expired sessions rejected.
- Clock events must reject invalid order, duplicate/replayed events and unsafe accuracy/mock-location signals where available.

## Logging and secrets

- Never log access tokens, OTPs, national identifiers, raw identity payloads, bank/payment credentials or precise location beyond operational need.
- CI secret scanning must stay enabled for commits and pull requests.
- Production secrets must live in platform secret stores, not Git or client bundles.
- Service-role keys must never be shipped to mobile/web clients.

## Web and API hardening

- Keep CSP/security headers, HSTS at production edge, frame protections and secure content-type/referrer policies.
- Validate all RPC inputs server-side and enforce bounded ranges for dates, rates, headcount, coordinates and pagination.
- Public lead/auth endpoints require rate limiting, bot/abuse controls and generic error responses.
- DAST staging target must be authenticated separately for worker and privileged Ops roles without production data.

## Mobile OWASP MASVS readiness

- No secrets or service-role credentials in the app bundle.
- Use secure OS-backed storage for sensitive session material where the auth SDK supports it.
- Foreground/background token refresh must not create uncontrolled background processing.
- Location permission UX must explain purpose and avoid persistent/background location unless explicitly required and approved.
- Release builds must disable debug-only endpoints/logging and use production-safe network configuration.
- Test rooted/jailbroken/debug/proxy scenarios as part of external mobile assessment where feasible.

## Supply chain and CI

- App CI must type-check/build web and mobile changes before integration.
- Security baseline must include secret scanning, SAST, dependency/vulnerability scanning and SQL authorization invariants.
- Generate and retain an SBOM for release candidates.
- Pin critical CI actions/dependencies where feasible and review dependency updates before release.

## Backup, restore and retention

- Define Supabase/Postgres backup frequency, retention, encryption and owner before production.
- Perform at least one staging restore drill before launch and record recovery time/results.
- Document deletion/anonymisation procedures for worker account closure and retention expiry.
- Verify audit records needed for legal/security purposes are retained independently of unnecessary profile data.

## Pen-test exit criteria

Before external penetration testing, require:

1. End-to-end staging flow works: OTP/onboarding/readiness -> shift discovery/acceptance -> GPS attendance -> timesheet -> supervisor review -> payroll-ready export.
2. App CI and Security baseline are green on the release candidate.
3. Production credentials remain disabled; staging test identities and synthetic client/site/shift data are used.
4. RLS/authorization regression suite passes against staging.
5. SBOM and dependency scan are captured.
6. DAST targets and test accounts are prepared for worker, supervisor/Ops and Finance/Admin roles.
7. Backup/restore checklist is completed.
8. Known residual risks and accepted business exceptions are documented.

## External blockers

Production launch still requires the applicable Singpass/MyInfo production approval and credentials, mobile signing/store approvals, and an independent external penetration test. These must not be bypassed by weakening staging controls.
