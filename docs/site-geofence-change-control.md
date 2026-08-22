# Site geofence change control

Attendance validation depends on the site latitude, longitude and `geofence_radius_m`, so those values are security-sensitive operational configuration rather than ordinary site metadata.

Migration `0030_site_geofence_change_control.sql` makes authenticated geofence changes pass through `update_site_geofence(...)`. Direct authenticated updates to those three columns are rejected by a trigger even though Ops retains the broader site-management RLS policy for non-geofence fields.

The RPC:

- requires an authenticated Ops/Admin caller through `public.is_ops()`;
- validates coordinate ranges and keeps the existing 25–2000 metre radius constraint;
- requires a non-empty change rationale, capped at 500 characters;
- locks the site row before mutation;
- enables the trigger bypass only for the target site and clears it immediately after the update;
- emits `site.geofence_changed` into `audit_events`;
- records the rationale, whether the location changed, and old/new radius values without duplicating exact coordinates into audit metadata.

Direct SQL maintenance remains possible when no application user identity is present (`auth.uid()` is null), preserving migration and controlled administrative workflows. Application code should never depend on that maintenance path.

This control matters because `record_clock_event(...)` treats the stored site geofence as authoritative when accepting or rejecting worker attendance. Any Ops UI that edits attendance boundaries must call `update_site_geofence(...)` rather than updating `sites.latitude`, `sites.longitude` or `sites.geofence_radius_m` directly.

Regression coverage is in `supabase/tests/site_geofence_change_control_checks.sql`.
