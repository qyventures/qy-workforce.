-- QY Workforce live headcount-gap alert safety invariants.
begin;

do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_live_headcount_gaps' and p.prosecdef
  ) then raise exception 'headcount gap feed must remain SECURITY DEFINER'; end if;

  if not has_function_privilege('authenticated','public.get_ops_live_headcount_gaps(integer,integer)','EXECUTE') then
    raise exception 'authenticated execute grant missing for headcount gap feed';
  end if;

  if has_function_privilege('anon','public.get_ops_live_headcount_gaps(integer,integer)','EXECUTE') then
    raise exception 'anon must not execute headcount gap feed';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_live_headcount_gaps'
      and pg_get_functiondef(p.oid) ilike '%is_ops()%'
      and pg_get_functiondef(p.oid) ilike '%shift_assignments%'
      and pg_get_functiondef(p.oid) ilike '%client_sla_policies%'
      and pg_get_functiondef(p.oid) ilike '%headcount_gap%'
  ) then raise exception 'headcount gap feed must remain Ops-only and evidence-based'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_live_headcount_gaps'
      and (
        pg_get_functiondef(p.oid) ilike '%insert into public.shift_assignments%'
        or pg_get_functiondef(p.oid) ilike '%update public.shifts%'
        or pg_get_functiondef(p.oid) ilike '%insert into public.communication_events%'
        or pg_get_functiondef(p.oid) ilike '%update public.worker_profiles%'
      )
  ) then raise exception 'headcount gap feed must remain read-only decision support'; end if;
end $$;

rollback;
