-- Structural regression checks for worker case-note governance.
-- Intended for CI review alongside migration linting.

select 1 where exists (
  select 1 from pg_proc where proname='add_worker_case_note'
);
select 1 where exists (
  select 1 from pg_proc where proname='resolve_worker_case_note'
);
select 1 where exists (
  select 1 from pg_class where relname='worker_case_notes' and relrowsecurity
);
