-- QY Workforce: close the legacy direct margin-view authorization bypass.
-- The aggregate view is internal only. Reporting is available through the bounded,
-- audited get_site_margin_report() RPC, which performs application-role checks.

revoke all on public.site_margin_summary from public;
revoke all on public.site_margin_summary from anon;
revoke all on public.site_margin_summary from authenticated;

comment on view public.site_margin_summary is
'Internal aggregate used by database/service workflows only. Client/site economics must be read through get_site_margin_report(date,date), which enforces privileged roles, bounded periods and audit logging.';
