# Margin reporting access boundary

Client/site margin data is commercially sensitive operational data. It must not be exposed through a generally readable authenticated view.

## Approved read path

Use `public.get_site_margin_report(p_start, p_end)` only. The RPC:

- permits `ops_manager`, `finance`, `admin`, and `auditor` roles only;
- limits a request to at most 366 days;
- rejects inappropriate future periods;
- returns aggregate client/site economics only, without worker identity; and
- writes a `margin_report.viewed` audit event for each successful access.

## Legacy view

`public.site_margin_summary` remains as an internal aggregate for database/service workflows, but direct privileges are revoked from `public`, `anon`, and `authenticated`.

This closes the historical bypass where any signed-in account could query the view without the RPC's role check, date bounds, or access audit.

## Security regression

`supabase/tests/margin_view_access_hardening_checks.sql` verifies that anonymous and authenticated roles cannot directly select the view while authenticated users retain permission to invoke the RPC, where application-role authorization is enforced.
