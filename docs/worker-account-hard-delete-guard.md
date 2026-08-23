# Worker account hard-delete boundary

## Why this exists

`public.profiles.id` references `auth.users(id)` with `ON DELETE CASCADE`, and the worker profile/evidence graph contains additional cascades. Without a database guard, deleting an authentication account can implicitly remove workforce records that may still be subject to payroll, dispute, audit, legal, or PDPA retention requirements.

QY Workforce therefore treats account closure and privacy erasure as a controlled data-lifecycle workflow, not as a direct row deletion operation.

## Control

Migration `202608232118_worker_account_hard_delete_guard.sql` installs a `BEFORE DELETE` trigger on `public.profiles`.

If the profile belongs to a worker, hard deletion is rejected. This also catches deletion that arrives indirectly from `auth.users ON DELETE CASCADE`.

`anon` and `authenticated` are explicitly denied `DELETE` on both `public.profiles` and `public.worker_profiles`.

The existing privacy-request and retention controls remain the supported path for erasure/minimisation. Those controls can preserve financial, audit, dispute, and legally retained records while removing or minimising personal evidence that is eligible for deletion.

There is deliberately no application-visible or session-setting bypass. If a final hard deletion is legally required after all retention obligations have expired, it must be handled as an explicit database-maintenance procedure with the guard deliberately disabled/re-enabled under change control.

## Security properties

- prevents worker account deletion from cascading through the operational evidence graph;
- preserves the privacy/retention state machine as the authoritative erasure boundary;
- denies direct end-user profile deletion;
- uses a `SECURITY DEFINER` trigger helper only so the worker lookup cannot be bypassed by RLS, with a pinned `pg_catalog, public` search path;
- revokes direct execution of the trigger helper from application roles;
- exposes no production credentials and adds no identity-provider coupling.

## Validation

`supabase/tests/worker_account_hard_delete_guard_checks.sql` verifies privilege revocation, trigger presence, trigger-function hardening, direct execution denial, and the absence of a session-setting bypass without fabricating Supabase Auth rows.
