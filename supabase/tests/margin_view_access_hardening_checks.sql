-- Regression checks for legacy margin-view access hardening.
-- These checks are intentionally metadata-focused so they can run without fixtures.

do $$
declare
  v_authenticated_select boolean;
  v_anon_select boolean;
  v_rpc_security_definer boolean;
  v_rpc_search_path text;
begin
  select has_table_privilege('authenticated','public.site_margin_summary','SELECT')
    into v_authenticated_select;
  if v_authenticated_select then
    raise exception 'authenticated must not have direct SELECT on site_margin_summary';
  end if;

  select has_table_privilege('anon','public.site_margin_summary','SELECT')
    into v_anon_select;
  if v_anon_select then
    raise exception 'anon must not have direct SELECT on site_margin_summary';
  end if;

  select p.prosecdef,
         coalesce(array_to_string(p.proconfig,','),'')
    into v_rpc_security_definer, v_rpc_search_path
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='get_site_margin_report'
    and pg_get_function_identity_arguments(p.oid)='p_start date, p_end date';

  if not coalesce(v_rpc_security_definer,false) then
    raise exception 'get_site_margin_report must remain SECURITY DEFINER';
  end if;

  if position('search_path=public' in replace(v_rpc_search_path,' ','')) = 0 then
    raise exception 'get_site_margin_report must pin search_path=public';
  end if;

  if not has_function_privilege('authenticated','public.get_site_margin_report(date,date)','EXECUTE') then
    raise exception 'authenticated role needs RPC execute so in-function role authorization can run';
  end if;
end;
$$;
