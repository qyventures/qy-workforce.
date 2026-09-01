-- Structural checks for the table-level assignment activation boundary.
begin;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.guard_shift_assignment_activation()'::regprocedure
  ) into v_definition;

  if v_definition not ilike '%pg_advisory_xact_lock%'
     or v_definition not ilike '%for update of sh%'
     or v_definition not ilike '%worker_has_deployment_prerequisites(new.worker_id)%'
     or v_definition not ilike '%worker_is_available_for_shift(%'
     or v_definition not ilike '%wr.approved%'
     or v_definition not ilike '%worker has overlapping shift%'
     or v_definition not ilike '%v_active_count >= v_shift.headcount%' then
    raise exception 'assignment activation guard is missing matching or capacity invariants';
  end if;

  -- Readiness must stay delegated to the existing predicate so identity,
  -- residency and work eligibility remain separately evaluated domains.
  if v_definition ilike '%identity_verified%'
     or v_definition ilike '%residency_verified%'
     or v_definition ilike '%work_eligibility =%' then
    raise exception 'assignment guard must not collapse identity, residency and eligibility outcomes';
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.shift_assignments'::regclass
      and tgname = 'trg_guard_shift_assignment_activation'
      and not tgisinternal
  ) then
    raise exception 'assignment activation trigger is missing';
  end if;

  if has_function_privilege(
       'anon', 'public.guard_shift_assignment_activation()', 'EXECUTE'
     )
     or has_function_privilege(
       'authenticated', 'public.guard_shift_assignment_activation()', 'EXECUTE'
     ) then
    raise exception 'assignment activation trigger function must not be API-callable';
  end if;

  if has_table_privilege('authenticated', 'public.shift_assignments', 'INSERT')
     or has_table_privilege('authenticated', 'public.shift_assignments', 'UPDATE')
     or has_table_privilege('authenticated', 'public.shift_assignments', 'DELETE') then
    raise exception 'assignment writes must remain behind audited RPC boundaries';
  end if;
end;
$$;

rollback;
