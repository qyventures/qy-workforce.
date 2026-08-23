# Supervisor site assignment control

Supervisor access to shifts, assignments and timesheet review is scoped through `supervisor_sites`. Because that mapping is an authorization boundary, changes must not be performed as ad-hoc table writes.

## Control model

- Direct authenticated INSERT/UPDATE/DELETE on `supervisor_sites` is revoked.
- Only Ops Manager/Admin callers may use the assignment RPCs.
- `assign_supervisor_site(...)` verifies that the target profile has the `supervisor` role and that the site is active.
- `revoke_supervisor_site(...)` removes an existing assignment only.
- Both operations require a non-empty business reason, truncated to 500 characters.
- Assignment and revocation emit `supervisor_site.assigned` and `supervisor_site.revoked` audit events.
- Audit metadata stores only the supervisor UUID, site UUID and rationale; it does not duplicate worker identity, attendance, payroll or geolocation data.
- Supervisors can read only their own mapping rows; privileged operations staff may read all mappings.

## Why this matters

Supervisor-site mappings drive authorization checks in site visibility and timesheet review. A weak mutation path could allow a supervisor to expand their own review scope or expose another client's workforce records. The RPC boundary keeps these changes explicit, role-validated and auditable.

## Staging validation

Before promotion, run `supabase/tests/supervisor_site_assignment_control_checks.sql` after all migrations and verify an end-to-end scenario using non-production users:

1. Ops assigns a supervisor to an active site with a rationale.
2. The supervisor can read the assigned site's review queue but not an unassigned site's queue.
3. A supervisor cannot invoke the assignment RPC to grant themselves another site.
4. Ops revokes the assignment with a rationale.
5. Access to that site's review queue disappears immediately.
6. Audit entries are present for both changes.
