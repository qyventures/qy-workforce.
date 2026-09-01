-- QY Workforce: explainable worker reliability scorecard for Ops.
-- This is decision support only. It does not alter deployability, assignments, or approvals.

create or replace function public.get_ops_worker_reliability_scorecard(
  p_worker_id uuid default null,
  p_lookback_days integer default 180,
  p_limit integer default 200
)
returns table(
  worker_id uuid,
  worker_name text,
  reliability_score integer,
  reliability_band text,
  reliability_points integer,
  reliability_events bigint,
  positive_events bigint,
  negative_events bigint,
  deployable boolean,
  window_start timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_lookback_days is null or p_lookback_days < 30 or p_lookback_days > 730 then
    raise exception 'lookback must be between 30 and 730 days';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'limit must be between 1 and 1000';
  end if;

  return query
  with aggregated as (
    select wp.user_id,
           coalesce(p.display_name, 'Worker') as worker_name,
           coalesce(sum(wre.points) filter (
             where wre.created_at >= now() - make_interval(days => p_lookback_days)
           ), 0)::integer as reliability_points,
           count(wre.*) filter (
             where wre.created_at >= now() - make_interval(days => p_lookback_days)
           ) as reliability_events,
           count(wre.*) filter (
             where wre.created_at >= now() - make_interval(days => p_lookback_days)
               and wre.points > 0
           ) as positive_events,
           count(wre.*) filter (
             where wre.created_at >= now() - make_interval(days => p_lookback_days)
               and wre.points < 0
           ) as negative_events
      from public.worker_profiles wp
      join public.profiles p on p.id = wp.user_id
      left join public.worker_reliability_events wre on wre.worker_id = wp.user_id
     where p_worker_id is null or wp.user_id = p_worker_id
     group by wp.user_id, p.display_name
  ), scored as (
    select a.*,
           greatest(0, least(100, 80 + a.reliability_points))::integer as reliability_score
      from aggregated a
  )
  select s.user_id,
         s.worker_name,
         s.reliability_score,
         case
           when s.reliability_score >= 90 then 'excellent'
           when s.reliability_score >= 80 then 'good'
           when s.reliability_score >= 65 then 'watch'
           else 'high_risk'
         end,
         s.reliability_points,
         s.reliability_events,
         s.positive_events,
         s.negative_events,
         public.worker_is_deployable(s.user_id),
         now() - make_interval(days => p_lookback_days)
    from scored s
   order by s.reliability_score desc, s.worker_name
   limit p_limit;
end;
$$;

revoke all on function public.get_ops_worker_reliability_scorecard(uuid,integer,integer) from public;
grant execute on function public.get_ops_worker_reliability_scorecard(uuid,integer,integer) to authenticated;

comment on function public.get_ops_worker_reliability_scorecard(uuid,integer,integer) is
  'Ops-only explainable reliability scorecard using audited reliability event points. Decision support only; does not change deployability or assignments.';
