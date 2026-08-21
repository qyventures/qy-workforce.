# QY Workforce

QY Workforce is a multi-role workforce operations platform for cleaners, casual workers, banquet/F&B staff, promoters, event crew and future manpower categories.

## V1 objective

Deliver one complete operational loop:

1. Worker registration
2. Singpass-ready identity verification abstraction
3. Residency/work-eligibility status
4. Role/skill selection and vetting
5. Training/approval
6. Shift creation and assignment
7. GPS/geofence clock-in and clock-out
8. Supervisor timesheet approval
9. Payroll-ready export
10. Client/site margin reporting

## Architecture

- Worker experience: installable PWA/mobile web
- Operations dashboard: web app
- Backend/database: Supabase/PostgreSQL
- Identity: pluggable provider abstraction; Singpass staging/production credentials supplied only through secrets
- Security: RBAC, RLS, audit logs, encryption, rate limiting, secure sessions, secret isolation and CI security checks

## Security / privacy principles

- No production credentials in source control
- Data minimisation and purpose limitation
- Sensitive identity and employment fields isolated from operational data
- Least privilege/RBAC and database row-level security
- Immutable security/audit events for sensitive actions
- No NRIC or Singpass token values in application logs
- Retention/deletion controls designed into the data model
- Separate dev/staging/production environments
- Independent penetration test required before production launch

## Repository status

Initial secure scaffold in progress. Singpass integration will be developed against public/staging documentation first and activated only after approved credentials are available.
