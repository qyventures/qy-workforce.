-- Regression checks for independent, internally consistent worker facts.
begin;
do $$
declare v_def text;
begin
  if not exists (select 1 from pg_constraint where conrelid='public.worker_profiles'::regclass and conname='worker_profiles_identity_timestamp_consistency') then raise exception 'identity verification timestamp invariant missing'; end if;
  if not exists (select 1 from pg_constraint where conrelid='public.worker_profiles'::regclass and conname='worker_profiles_residency_category_consistency') then raise exception 'residency category invariant missing'; end if;
  if not exists (select 1 from pg_constraint where conrelid='public.worker_profiles'::regclass and conname='worker_profiles_eligibility_evidence_consistency') then raise exception 'eligibility evidence invariant missing'; end if;
  select pg_get_functiondef('public.complete_identity_verification_staging(uuid,text,boolean,text,boolean,public.eligibility_status,text)'::regprocedure) into v_def;
  if position('eligibility_checked_at=casewhenp_work_eligibility<>''unknown''thennow()elsenullend' in replace(v_def,' ',''))=0
     or position('eligibility_source=casewhenp_work_eligibility<>''unknown''thenv_eligibility_sourceelsenullend' in replace(v_def,' ',''))=0 then raise exception 'unknown eligibility must clear stale evidence'; end if;
  if position('verified residency category required' in lower(v_def))=0 then raise exception 'verified residency must have a category'; end if;
end $$;
rollback;
