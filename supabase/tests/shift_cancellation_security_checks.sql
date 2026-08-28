begin;
do $$
declare v_def text;
begin
  if to_regprocedure('public.cancel_shift(uuid,text)') is null then raise exception 'cancel_shift(uuid,text) is missing'; end if;
  select pg_get_functiondef('public.cancel_shift(uuid,text)'::regprocedure) into v_def;
  if position('security definer' in lower(v_def)) = 0 or position('auth.uid()' in v_def) = 0
     or position('public.is_ops()' in v_def) = 0 or position('for update' in lower(v_def)) = 0 then
    raise exception 'shift cancellation must authenticate, authorise and lock inside a security-definer RPC';
  end if;
  if position('only draft or open shifts can be cancelled' in lower(v_def)) = 0
     or position('started shifts cannot be cancelled' in lower(v_def)) = 0
     or position('shift with attendance cannot be cancelled' in lower(v_def)) = 0 then
    raise exception 'shift cancellation lifecycle and attendance guards are missing';
  end if;
  if position('set cancelled_at = now()' in lower(v_def)) = 0 or position('shift.cancelled' in v_def) = 0
     or position('affected_assignment_count' in v_def) = 0 then
    raise exception 'shift cancellation must deactivate assignments and record aggregate audit evidence';
  end if;
  if position('delete from' in lower(v_def)) > 0 then raise exception 'shift cancellation must not delete workforce history'; end if;
  if has_function_privilege('anon', 'public.cancel_shift(uuid,text)', 'EXECUTE') then raise exception 'anonymous users must not cancel shifts'; end if;
  if not has_function_privilege('authenticated', 'public.cancel_shift(uuid,text)', 'EXECUTE') then raise exception 'authenticated Ops callers must reach the authorised RPC'; end if;
end $$;
rollback;
