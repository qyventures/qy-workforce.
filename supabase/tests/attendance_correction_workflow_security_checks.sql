-- Structural security checks for audited attendance corrections.
do $$
begin
  if to_regclass('public.attendance_correction_requests') is null then
    raise exception 'attendance_correction_requests missing';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='attendance_correction_requests' and c.relrowsecurity
  ) then raise exception 'RLS not enabled on attendance_correction_requests'; end if;

  if has_table_privilege('authenticated','public.attendance_correction_requests','INSERT')
     or has_table_privilege('authenticated','public.attendance_correction_requests','UPDATE')
     or has_table_privilege('authenticated','public.attendance_correction_requests','DELETE') then
    raise exception 'authenticated has direct mutation privilege on correction requests';
  end if;

  if not has_function_privilege('authenticated','public.request_attendance_correction(uuid,timestamptz,timestamptz,text)','EXECUTE') then
    raise exception 'worker correction request RPC not executable';
  end if;
  if not has_function_privilege('authenticated','public.review_attendance_correction(uuid,text,text)','EXECUTE') then
    raise exception 'review correction RPC not executable';
  end if;
  if not has_function_privilege('authenticated','public.cancel_own_attendance_correction(uuid)','EXECUTE') then
    raise exception 'cancel correction RPC not executable';
  end if;
  if not has_function_privilege('authenticated','public.get_attendance_correction_review_queue()','EXECUTE') then
    raise exception 'correction review queue RPC not executable';
  end if;
  if pg_get_functiondef('public.get_attendance_correction_review_queue()'::regprocedure) not like '%supervisor_sites%' then
    raise exception 'correction review queue site scope missing';
  end if;
  if pg_get_functiondef('public.get_attendance_correction_review_queue()'::regprocedure) not like '%Worker #%' then
    raise exception 'correction review queue worker masking missing';
  end if;

  if pg_get_functiondef('public.review_attendance_correction(uuid,text,text)'::regprocedure) not like '%requester cannot review own request%' then
    raise exception 'separation-of-duties guard missing';
  end if;
  if pg_get_functiondef('public.review_attendance_correction(uuid,text,text)'::regprocedure) not like '%supervisor not assigned to site%' then
    raise exception 'site authorization guard missing';
  end if;
  if pg_get_functiondef('public.review_attendance_correction(uuid,text,text)'::regprocedure) not like '%approved/submitted timesheet must be handled through payroll adjustment workflow%' then
    raise exception 'financial-state integrity guard missing';
  end if;
  if pg_get_functiondef('public.review_attendance_correction(uuid,text,text)'::regprocedure) not like '%supervisor_adjustment%' then
    raise exception 'append-only adjustment evidence missing';
  end if;
end $$;
