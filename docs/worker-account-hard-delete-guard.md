# Worker account hard-delete boundary

## Why this exists

`public.profiles.id` references `auth.users(id)` with `ON DELETE CASCADE`, and the worker profile/evidence graph contains additional cascades. Without a database guard, deleting an authentication account can implicitly remove workforce records that are still subject to payroll, dispute, audit, legal, or PDPA retention requirements.

QY Workforce therefore treats account closure and privacy erasure as a controlled data-lifecycle workflow, not as a direct row deletion operation.

## Control

Migration `202608232118_worker_account_hard_delete_guard.sql` installs a `BEFORE DELETE` trigger on `public.profiles`.

If the profile belongs to a worker, hard deletion is rejected. This also catches deletion that arrives indirectly from `auth.users ON DELETE CASCADE`.

`anon` and `authenticated` are explicitly denied `DELETE` on both `public.profiles` and `public.worker_profiles`.

The existing privacy-request and retention controls remain the supported path for erasure/minimisation. Those controls can preserve financial, audit, dispute, and legally retained records while removing or minimising personal evidence that is eligible for deletion.

## Controlled maintenance escape hatch

A trusted database operator may set the transaction/session setting:

`app.allow_worker_hard_delete = on`

This is deliberately not exposed through an RPC or application role. It exists only for controlled database maintenance after retention/legal requirements have been checked. Application code must not set or depend on it.

## Security properties

- prevents worker account deletion from cascading through the operational evidence graph;
- preserves the privacy/retention state machine as the authoritative erasure boundary;
- denies direct end-user profile deletion;
- uses a pinned `search_path` trigger function;
- exposes no production credentials and adds no identity-provider coupling;
- leaves non-worker profile deletion subject to the existing foreign-key/audit constraints.

## Validation

`supabase/tests/worker_account_hard_delete_guard_checks.sql` verifies privilege revocation, trigger presence, trigger-function hardening, absence of direct authenticated execution, and the explicit maintenance-override requirement without fabricating Supabase Auth rows.
