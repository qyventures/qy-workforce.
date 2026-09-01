-- Structural safety checks for MFA-gated privileged access changes.

do $$
declare
  v_migration text;
begin
  select pg_get_functiondef('public.is_admin_mfa()'::regprocedure) into v_migration;
  if position('aal2' in v_migration)=0 then raise exception 'is_admin_mfa must require aal2'; end if;
  if position('role = ''admin''' in v_migration)=0 and position('role = ''admin''::public.user_role' in v_migration)=0 then
    raise exception 'is_admin_mfa must require admin role';
  end if;
end $$;

do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.admin_request_privileged_access_change(uuid,text,text)'::regprocedure) into v_sql;
  if position('is_admin_mfa' in v_sql)=0 then raise exception 'request RPC must require MFA admin'; end if;
  if position('self role changes are not permitted' in v_sql)=0 then raise exception 'request RPC must deny self role change'; end if;
  if position('pending role change already exists' in v_sql)=0 then raise exception 'request RPC must prevent duplicate pending requests'; end if;
end $$;

do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.admin_review_privileged_access_change(uuid,text,text)'::regprocedure) into v_sql;
  if position('is_admin_mfa' in v_sql)=0 then raise exception 'review RPC must require MFA admin'; end if;
  if position('requester cannot approve or reject own request' in v_sql)=0 then raise exception 'review RPC must enforce separation of duties'; end if;
  if position('cannot remove the last admin' in v_sql)=0 then raise exception 'review RPC must preserve a final admin'; end if;
  if position('update public.profiles' in lower(v_sql))=0 then raise exception 'approved review must be the controlled role mutation path'; end if;
end $$;

do $$
declare v_rls boolean;
begin
  select relrowsecurity into v_rls from pg_class where oid='public.privileged_access_change_requests'::regclass;
  if not v_rls then raise exception 'privileged access requests must have RLS enabled'; end if;
end $$;

do $$
declare v_has_write boolean;
begin
  select has_table_privilege('authenticated','public.privileged_access_change_requests','insert,update,delete') into v_has_write;
  if v_has_write then raise exception 'authenticated must not have direct writes to privileged access requests'; end if;
end $$;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'admin_request_privileged_access_change',
    'admin_review_privileged_access_change',
    'admin_cancel_own_privileged_access_change'
  ) and p.prosecdef;
  if v_count <> 3 then raise exception 'all privileged access mutation RPCs must be SECURITY DEFINER'; end if;
end $$;
