-- Static regression checks for controlled supervisor-to-site authorization.
-- Run after migrations in CI/staging.

do $$
declare
  v_def text;
  v_count integer;
begin
  select pg_get_functiondef('public.assign_supervisor_site(uuid,uuid,text)'::regprocedure)
  into v_def;
  if position('SECURITY DEFINER' in upper(v_def)) = 0 then
    raise exception 'assign_supervisor_site must be SECURITY DEFINER';
  end if;
  if position('SET search_path TO ''public''' in v_def) = 0
     and position('SET search_path = public' in v_def) = 0 then
    raise exception 'assign_supervisor_site must pin search_path';
  end if;
  if position('public.is_ops()' in v_def) = 0 then
    raise exception 'assign_supervisor_site must enforce ops/admin authorization';
  end if;
  if position('target user is not a supervisor' in v_def) = 0 then
    raise exception 'assign_supervisor_site must validate supervisor role';
  end if;
  if position('cannot assign inactive site' in v_def) = 0 then
    raise exception 'assign_supervisor_site must reject inactive sites';
  end if;
  if position('supervisor_site.assigned' in v_def) = 0 then
    raise exception 'assign_supervisor_site must emit audit event';
  end if;

  select pg_get_functiondef('public.revoke_supervisor_site(uuid,uuid,text)'::regprocedure)
  into v_def;
  if position('SECURITY DEFINER' in upper(v_def)) = 0 then
    raise exception 'revoke_supervisor_site must be SECURITY DEFINER';
  end if;
  if position('public.is_ops()' in v_def) = 0 then
    raise exception 'revoke_supervisor_site must enforce ops/admin authorization';
  end if;
  if position('revocation reason required' in v_def) = 0 then
    raise exception 'revoke_supervisor_site must require rationale';
  end if;
  if position('supervisor_site.revoked' in v_def) = 0 then
    raise exception 'revoke_supervisor_site must emit audit event';
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema='public'
    and table_name='supervisor_sites'
    and grantee='authenticated'
    and privilege_type in ('INSERT','UPDATE','DELETE');
  if v_count <> 0 then
    raise exception 'authenticated must not have direct supervisor_sites mutation grants';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='supervisor_sites'
      and policyname='privileged read supervisor sites'
  ) then
    raise exception 'supervisor_sites read policy missing';
  end if;
end;
$$;
