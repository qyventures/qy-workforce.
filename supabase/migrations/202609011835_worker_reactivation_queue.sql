-- QY Workforce: consent-aware worker reactivation queue for Ops.
-- Decision support only: this function never sends messages, changes worker status, or assigns shifts.

create or replace function public.get_ops_worker_reactivation_queue(
  p_inactive_days integer default 30,
  p_limit integer default 200
)
returns table(
  worker_id uuid,
  worker_name text,
  last_assignment_at timestamptz,
  days_inactive integer,
  reliability_score integer,
  deployable boolean,
  whatsapp_opted_in boolean,
  email_opted_in boolean,
  future_availability boolean,
  suggested_action text,
  reactivation_priority integer
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_inactive_days is null or p_inactive_days < 14 or p_inactive_days > 365 then
    raise exception 'inactive days must be between 14 and 365';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'limit must be between 1 and 1000';
  end if;

  return query
  with worker_activity as (
    select wp.user_id,
           coalesce(p.display_name,'Worker') worker_name,
           max(sh.ends_at) filter (
             where sa.cancelled_at is null
               and sh.status in ('assigned','completed','cancelled')
               and sh.ends_at <= now()
           ) last_assignment_at
      from public.worker_profiles wp
      join public.profiles p on p.id=wp.user_id
      left join public.shift_assignments sa on sa.worker_id=wp.user_id
      left join public.shifts sh on sh.id=sa.shift_id
     group by wp.user_id,p.display_name
  ), scored as (
    select wa.*,
           greatest(0,least(100,80+coalesce((
             select sum(wre.points) from public.worker_reliability_events wre
              where wre.worker_id=wa.user_id
                and wre.created_at>=now()-interval '180 days'
           ),0)))::integer reliability_score,
           public.worker_is_deployable(wa.user_id) deployable,
           exists(
             select 1 from public.communication_preferences cp
              where cp.subject_type='worker' and cp.subject_id=wa.user_id
                and cp.channel='whatsapp' and cp.status='opted_in'
           ) whatsapp_opted_in,
           exists(
             select 1 from public.communication_preferences cp
              where cp.subject_type='worker' and cp.subject_id=wa.user_id
                and cp.channel='email' and cp.status='opted_in'
           ) email_opted_in,
           exists(
             select 1 from public.worker_availability av
              where av.worker_id=wa.user_id
                and av.availability_type in ('available','preferred')
                and av.ends_at>now()
           ) future_availability
      from worker_activity wa
  ), dormant as (
    select s.*,
           case when s.last_assignment_at is null then 9999
                else floor(extract(epoch from (now()-s.last_assignment_at))/86400)::integer end days_inactive
      from scored s
     where s.last_assignment_at is null
        or s.last_assignment_at <= now()-make_interval(days=>p_inactive_days)
  )
  select d.user_id,d.worker_name,d.last_assignment_at,d.days_inactive,d.reliability_score,d.deployable,
         d.whatsapp_opted_in,d.email_opted_in,d.future_availability,
         case
           when not d.deployable then 'review_readiness_before_contact'
           when not (d.whatsapp_opted_in or d.email_opted_in) then 'no_outbound_consent_manual_review'
           when d.future_availability then 'priority_human_reactivation'
           else 'human_reactivation_check_availability'
         end suggested_action,
         case
           when not d.deployable then 4
           when not (d.whatsapp_opted_in or d.email_opted_in) then 3
           when d.future_availability and d.reliability_score>=80 then 1
           else 2
         end reactivation_priority
    from dormant d
   order by reactivation_priority asc,d.reliability_score desc,d.days_inactive desc,d.worker_name
   limit p_limit;
end;
$$;

revoke all on function public.get_ops_worker_reactivation_queue(integer,integer) from public;
grant execute on function public.get_ops_worker_reactivation_queue(integer,integer) to authenticated;

comment on function public.get_ops_worker_reactivation_queue(integer,integer) is
  'Ops-only consent-aware dormant-worker queue. Decision support only; never sends messages, assigns shifts, or changes worker status.';
