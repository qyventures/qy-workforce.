-- Static/security regression checks for aggregate margin reporting.
-- Intended for CI inspection alongside migration execution tests.

begin;

-- Function must remain SECURITY DEFINER with a fixed search_path and authenticated-only execution.
do $$
declare
  v_def text;
  v_acl aclitem[];
begin
  select pg_get_functiondef(p.oid), p.proacl
    into v_def, v_acl
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='get_site_margin_report'
    and pg_get_function_identity_arguments(p.oid)='p_start date, p_end date';

  if v_def is null then raise exception 'get_site_margin_report missing'; end if;
  if position('SECURITY DEFINER' in upper(v_def))=0 then raise exception 'margin report must be security definer'; end if;
  if position('SET search_path TO ''public''' in v_def)=0 and position('SET search_path TO public' in v_def)=0 then
    raise exception 'margin report must pin search_path';
  end if;
  if position('margin_report.viewed' in v_def)=0 then raise exception 'margin report access must be audited'; end if;
  if position('366' in v_def)=0 then raise exception 'margin report must bound date range'; end if;
  if position('worker_id' in lower(v_def))>0 or position('full_name' in lower(v_def))>0 then
    raise exception 'margin report must not expose worker identity';
  end if;
end $$;

rollback;
