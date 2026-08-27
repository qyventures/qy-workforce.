-- Regression checks for the Ops shift creation and publication boundary.

begin;

do $$
declare
  v_create_def text;
  v_open_def text;
begin
  select pg_get_functiondef(
    'public.create_shift_draft(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric)'::regprocedure
  ) into v_create_def;
  select pg_get_functiondef('public.open_shift(uuid)'::regprocedure) into v_open_def;

  if position('security definer' in lower(v_create_def)) = 0
     or position('auth.uid()' in v_create_def) = 0
     or position('public.is_ops()' in v_create_def) = 0 then
    raise exception 'shift creation must enforce authenticated Ops access inside the RPC';
  end if;

  if position('shift start cannot be in the past' in lower(v_create_def)) = 0
     or position('shift duration exceeds 24 hours' in lower(v_create_def)) = 0
     or position('headcount must be between 1 and 500' in lower(v_create_def)) = 0
     or position('rate exceeds configured safety limit' in lower(v_create_def)) = 0 then
    raise exception 'shift creation safety bounds must remain server-enforced';
  end if;

  if position('site or client is inactive' in lower(v_create_def)) = 0
     or position('role is inactive' in lower(v_create_def)) = 0
     or position('shift.draft_created' in v_create_def) = 0 then
    raise exception 'shift creation must validate active demand configuration and audit the action';
  end if;

  if position('security definer' in lower(v_open_def)) = 0
     or position('public.is_ops()' in v_open_def) = 0
     or position('for update' in lower(v_open_def)) = 0
     or position('only draft shifts can be opened' in lower(v_open_def)) = 0
     or position('shift.opened' in v_open_def) = 0 then
    raise exception 'shift publication must authorise, lock, validate state and audit the action';
  end if;

  if has_function_privilege('anon',
      'public.create_shift_draft(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric)', 'EXECUTE')
     or has_function_privilege('anon', 'public.open_shift(uuid)', 'EXECUTE') then
    raise exception 'anonymous users must not create or publish shifts';
  end if;

  if not has_function_privilege('authenticated',
      'public.create_shift_draft(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.open_shift(uuid)', 'EXECUTE') then
    raise exception 'authenticated staff must be able to reach the internally authorised shift RPCs';
  end if;

  if has_table_privilege('authenticated', 'public.shifts', 'INSERT')
     or has_table_privilege('authenticated', 'public.shifts', 'UPDATE')
     or has_table_privilege('authenticated', 'public.shifts', 'DELETE') then
    raise exception 'authenticated clients must not bypass audited shift RPCs with direct writes';
  end if;
end $$;

rollback;
