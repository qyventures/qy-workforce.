-- QY Workforce: deterministic fulfilment-risk cockpit and safe replacement suggestions.
-- AI may summarize these outputs, but final assignment remains an explicit Ops action.

create or replace function public.get_ops_fulfilment_risk(
  p_from timestamptz default now(),
  p_to timestamptz default now() + interval '30 days'
)
returns table(
  shift_id uuid,
  client_name text,
  site_name text,
  role_name text,
  starts_at timestamptz,
  headcount integer,
  filled_count bigint,
  gap_count integer,
  fill_percent numeric,
  hours_to_start numeric,
  risk_level text,
  risk_reasons text[]
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_from is null or p_to is null or p_to <= p_from then raise exception 'invalid risk time range'; end if;
  if p_to - p_from > interval '366 days' then raise exception 'risk time range exceeds 366 days'; end if;

  return query
  with q as (
    select sh.id, c.name client_name, si.name site_name, r.name role_name,
           sh.starts_at, sh.headcount,
           count(sa.id) filter (where sa.cancelled_at is null) filled_count
      from public.shifts sh
      join public.sites si on si.id=sh.site_id
      join public.clients c on c.id=si.client_id
      join public.roles r on r.id=sh.role_id
      left join public.shift_assignments sa on sa.shift_id=sh.id
     where sh.starts_at >= p_from and sh.starts_at < p_to
       and sh.status in ('open','assigned')
     group by sh.id,c.name,si.name,r.name
  ), scored as (
    select q.*,
           greatest(q.headcount-q.filled_count::integer,0) gap_count,
           round(100.0*q.filled_count/greatest(q.headcount,1),1) fill_percent,
           round(extract(epoch from (q.starts_at-now()))/3600.0,1) hours_to_start
      from q
  )
  select s.id,s.client_name,s.site_name,s.role_name,s.starts_at,s.headcount,s.filled_count,
         s.gap_count,s.fill_percent,s.hours_to_start,
         case
           when s.gap_count > 0 and s.hours_to_start <= 12 then 'critical'
           when s.gap_count > 0 and s.hours_to_start <= 24 then 'high'
           when s.gap_count > 0 and (s.hours_to_start <= 72 or s.fill_percent < 85) then 'medium'
           else 'low'
         end,
         array_remove(array[
           case when s.gap_count > 0 then format('%s unfilled slot(s)',s.gap_count) end,
           case when s.hours_to_start <= 12 then 'starts within 12 hours'
                when s.hours_to_start <= 24 then 'starts within 24 hours'
                when s.hours_to_start <= 72 then 'starts within 72 hours' end,
           case when s.fill_percent < 85 then 'fill rate below 85%' end
         ],null)
    from scored s
   order by case
     when s.gap_count > 0 and s.hours_to_start <= 12 then 1
     when s.gap_count > 0 and s.hours_to_start <= 24 then 2
     when s.gap_count > 0 and (s.hours_to_start <= 72 or s.fill_percent < 85) then 3
     else 4 end,
     s.starts_at;
end;
$$;
revoke all on function public.get_ops_fulfilment_risk(timestamptz,timestamptz) from public;
grant execute on function public.get_ops_fulfilment_risk(timestamptz,timestamptz) to authenticated;

create or replace function public.get_ops_replacement_candidates(
  p_shift_id uuid,
  p_limit integer default 20
)
returns table(
  worker_id uuid,
  worker_name text,
  reliability_score integer,
  preferred_available boolean,
  available_cover boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_role uuid;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then raise exception 'invalid candidate limit'; end if;

  select role_id,starts_at,ends_at into v_role,v_starts,v_ends
    from public.shifts where id=p_shift_id and status in ('open','assigned');
  if v_role is null then raise exception 'shift not found or not fillable'; end if;

  return query
  with eligible as (
    select wp.user_id,
           coalesce(p.display_name,'Worker') worker_name,
           greatest(0,least(100,80+coalesce(sum(wre.points) filter (where wre.created_at>=now()-interval '180 days'),0)))::integer reliability_score,
           exists(select 1 from public.worker_availability wa where wa.worker_id=wp.user_id and wa.availability_type='preferred' and wa.starts_at<=v_starts and wa.ends_at>=v_ends) preferred_available,
           exists(select 1 from public.worker_availability wa where wa.worker_id=wp.user_id and wa.availability_type in ('available','preferred') and wa.starts_at<=v_starts and wa.ends_at>=v_ends) available_cover
      from public.worker_profiles wp
      join public.profiles p on p.id=wp.user_id
      join public.worker_roles wr on wr.worker_id=wp.user_id and wr.role_id=v_role and wr.approved
      left join public.worker_reliability_events wre on wre.worker_id=wp.user_id
     where public.worker_is_deployable(wp.user_id)
       and not exists(select 1 from public.worker_absences a where a.worker_id=wp.user_id and a.status in ('reported','reviewed','approved') and a.starts_at<v_ends and a.ends_at>v_starts)
       and not exists(
         select 1 from public.shift_assignments sa join public.shifts sh on sh.id=sa.shift_id
          where sa.worker_id=wp.user_id and sa.cancelled_at is null and sh.starts_at<v_ends and sh.ends_at>v_starts
       )
       and not exists(select 1 from public.shift_assignments sa where sa.shift_id=p_shift_id and sa.worker_id=wp.user_id and sa.cancelled_at is null)
     group by wp.user_id,p.display_name
  )
  select e.user_id,e.worker_name,e.reliability_score,e.preferred_available,e.available_cover
    from eligible e
   order by e.preferred_available desc,e.available_cover desc,e.reliability_score desc,e.worker_name
   limit p_limit;
end;
$$;
revoke all on function public.get_ops_replacement_candidates(uuid,integer) from public;
grant execute on function public.get_ops_replacement_candidates(uuid,integer) to authenticated;

comment on function public.get_ops_fulfilment_risk(timestamptz,timestamptz) is 'Ops-only deterministic fulfilment risk cockpit; no automatic assignment.';
comment on function public.get_ops_replacement_candidates(uuid,integer) is 'Ops-only ranked replacement suggestions. Recommendations never bypass explicit assignment approval.';