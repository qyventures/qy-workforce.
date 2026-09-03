select 1 where exists (select 1 from information_schema.columns where table_schema='public' and table_name='employer_leads' and column_name='sheet_sync_status');
select 1 where exists (select 1 from pg_class where relname='lead_handoff_events' and relrowsecurity);
