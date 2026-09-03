-- Structural/security regression checks for 0026_privacy_request_state_machine.sql.
-- These checks intentionally avoid production credentials and destructive data setup.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'review_privacy_request'
      and p.prosecdef
      and array_to_string(p.proconfig, ',') like '%search_path=public%'
  ) then
    raise exception 'review_privacy_request must be SECURITY DEFINER with search_path=public';
  end if;
end $$;

do $$
begin
  if not has_function_privilege('authenticated', 'public.review_privacy_request(uuid,text,text,boolean)', 'EXECUTE') then
    raise exception 'authenticated role must have execute on review_privacy_request';
  end if;
  if has_table_privilege('authenticated', 'public.privacy_requests', 'INSERT')
     or has_table_privilege('authenticated', 'public.privacy_requests', 'UPDATE')
     or has_table_privilege('authenticated', 'public.privacy_requests', 'DELETE') then
    raise exception 'privacy_requests direct authenticated mutation must stay revoked';
  end if;
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.review_privacy_request(uuid,text,text,boolean)'::regprocedure)
    into v_def;

  if position('invalid privacy request transition' in v_def) = 0 then
    raise exception 'privacy state transition guard missing';
  end if;
  if position('privacy request is terminal' in v_def) = 0 then
    raise exception 'terminal-state guard missing';
  end if;
  if position('coalesce(requester_id, worker_id)' in lower(v_def)) = 0 then
    raise exception 'review must support requester_id and legacy worker_id';
  end if;
  if position('reason required when changing retention hold' in v_def) = 0 then
    raise exception 'retention-hold rationale guard missing';
  end if;
  if position('erasure cannot be completed while retention hold is active' in v_def) = 0 then
    raise exception 'erasure retention-hold guard missing';
  end if;
  if position('completion reason required for erasure' in v_def) = 0 then
    raise exception 'erasure completion evidence guard missing';
  end if;
  if position('privacy_request.transitioned' in v_def) = 0 then
    raise exception 'privacy transition audit event missing';
  end if;
end $$;

rollback;
