-- Static regression checks for migration 0025_site_geofence_change_control.sql.
-- These checks fail loudly if the audited geofence mutation boundary is removed or weakened.

begin;

select 1 / case when to_regprocedure('public.update_site_geofence(uuid,numeric,numeric,integer,text)') is not null then 1 else 0 end;
select 1 / case when to_regprocedure('public.guard_site_geofence_update()') is not null then 1 else 0 end;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.update_site_geofence(uuid,numeric,numeric,integer,text)'::regprocedure) into v_def;
  if v_def not ilike '%SECURITY DEFINER%' then
    raise exception 'update_site_geofence must remain SECURITY DEFINER';
  end if;
  if v_def not ilike '%SET search_path TO public%' and v_def not ilike '%SET search_path = public%' then
    raise exception 'update_site_geofence must pin search_path';
  end if;
  if v_def not ilike '%public.is_ops()%' then
    raise exception 'update_site_geofence must enforce Ops/Admin authorisation';
  end if;
  if v_def not ilike '%change reason required%' then
    raise exception 'update_site_geofence must require a rationale';
  end if;
  if v_def not ilike '%site.geofence_changed%' then
    raise exception 'update_site_geofence must emit an audit event';
  end if;
end $$;

do $$
begin
  if has_function_privilege('anon', 'public.update_site_geofence(uuid,numeric,numeric,integer,text)', 'EXECUTE') then
    raise exception 'anon must not execute update_site_geofence';
  end if;
  if not has_function_privilege('authenticated', 'public.update_site_geofence(uuid,numeric,numeric,integer,text)', 'EXECUTE') then
    raise exception 'authenticated role should be able to invoke update_site_geofence for in-function role checks';
  end if;
end $$;

do $$
declare
  v_trigger_count integer;
begin
  select count(*) into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname='sites'
    and t.tgname='sites_geofence_change_guard'
    and not t.tgisinternal;
  if v_trigger_count <> 1 then
    raise exception 'sites_geofence_change_guard trigger must exist exactly once';
  end if;
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.update_site_geofence(uuid,numeric,numeric,integer,text)'::regprocedure) into v_def;
  if v_def ilike '%old_latitude%' or v_def ilike '%new_latitude%' or v_def ilike '%old_longitude%' or v_def ilike '%new_longitude%' then
    raise exception 'audit metadata must not duplicate exact geofence coordinates';
  end if;
end $$;

rollback;
