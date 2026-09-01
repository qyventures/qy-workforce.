-- QY Workforce worker-reactivation safety invariants.
begin;

do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_worker_reactivation_queue' and p.prosecdef
  ) then raise exception 'reactivation queue must remain SECURITY DEFINER'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_worker_reactivation_queue'
      and pg_get_functiondef(p.oid) ilike '%is_ops()%'
      and pg_get_functiondef(p.oid) ilike '%communication_preferences%'
      and pg_get_functiondef(p.oid) ilike '%opted_in%'
      and pg_get_functiondef(p.oid) ilike '%worker_is_deployable%'
  ) then raise exception 'reactivation queue must remain Ops-only, consent-aware and deployability-aware'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_ops_worker_reactivation_queue'
      and (pg_get_functiondef(p.oid) ilike '%insert into public.communication_events%'
        or pg_get_functiondef(p.oid) ilike '%shift_assignments(%'
        or pg_get_functiondef(p.oid) ilike '%update public.worker_profiles%')
  ) then raise exception 'reactivation queue must not send, assign or mutate worker status'; end if;
end $$;

rollback;
