-- Structural regression checks for accepted-shift term integrity.

do $$
begin
  if to_regprocedure('public.guard_accepted_shift_terms()') is null then
    raise exception 'guard_accepted_shift_terms() is missing';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='shifts'
      and t.tgname='trg_guard_accepted_shift_terms'
      and not t.tgisinternal
  ) then
    raise exception 'accepted shift terms trigger is missing';
  end if;

  if has_function_privilege('anon','public.guard_accepted_shift_terms()','EXECUTE') then
    raise exception 'anon must not execute accepted shift term guard directly';
  end if;

  if has_function_privilege('authenticated','public.guard_accepted_shift_terms()','EXECUTE') then
    raise exception 'authenticated must not execute accepted shift term guard directly';
  end if;
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.guard_accepted_shift_terms()'::regprocedure) into v_def;

  if position('accepted_at is not null' in lower(v_def)) = 0
     or position('cancelled_at is null' in lower(v_def)) = 0 then
    raise exception 'guard must scope to active accepted assignments';
  end if;

  if position('worker_rate' in v_def) = 0
     or position('client_rate' in v_def) = 0
     or position('starts_at' in v_def) = 0
     or position('ends_at' in v_def) = 0
     or position('site_id' in v_def) = 0
     or position('role_id' in v_def) = 0 then
    raise exception 'guard is missing one or more protected shift terms';
  end if;

  if position('headcount' in v_def) = 0 then
    raise exception 'guard must protect accepted capacity';
  end if;
end $$;
