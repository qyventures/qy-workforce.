-- QY Workforce: secure shift creation/publishing boundary.
-- Keeps demand creation server-authoritative and prevents direct client writes.

alter table public.clients enable row level security;
alter table public.sites enable row level security;
alter table public.roles enable row level security;
alter table public.shifts enable row level security;

-- Privileged staff may inspect demand configuration; workers continue to use scoped RPCs.
create policy "privileged read clients" on public.clients
for select using (public.is_privileged());

create policy "privileged read sites" on public.sites
for select using (public.is_privileged());

create policy "privileged read roles" on public.roles
for select using (public.is_privileged());

create policy "privileged read shifts" on public.shifts
for select using (public.is_privileged());

create or replace function public.create_shift_draft(
  p_site_id uuid,
  p_role_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_headcount integer,
  p_worker_rate numeric,
  p_client_rate numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift_id uuid;
  v_site_active boolean;
  v_client_active boolean;
  v_role_active boolean;
  v_margin_pct numeric;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if not public.is_ops() then
    raise exception 'not authorised';
  end if;

  if p_site_id is null or p_role_id is null then
    raise exception 'site and role are required';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'invalid shift time range';
  end if;
  if p_starts_at < now() - interval '15 minutes' then
    raise exception 'shift start cannot be in the past';
  end if;
  if p_ends_at - p_starts_at > interval '24 hours' then
    raise exception 'shift duration exceeds 24 hours';
  end if;
  if p_headcount is null or p_headcount < 1 or p_headcount > 500 then
    raise exception 'headcount must be between 1 and 500';
  end if;
  if p_worker_rate is null or p_client_rate is null or p_worker_rate < 0 or p_client_rate < 0 then
    raise exception 'rates must be non-negative';
  end if;
  if p_worker_rate > 1000 or p_client_rate > 1000 then
    raise exception 'rate exceeds configured safety limit';
  end if;

  select s.active, c.active
    into v_site_active, v_client_active
  from public.sites s
  join public.clients c on c.id = s.client_id
  where s.id = p_site_id;

  if v_site_active is null then raise exception 'site not found'; end if;
  if not v_site_active or not v_client_active then raise exception 'site or client is inactive'; end if;

  select active into v_role_active from public.roles where id = p_role_id;
  if v_role_active is null then raise exception 'role not found'; end if;
  if not v_role_active then raise exception 'role is inactive'; end if;

  insert into public.shifts(
    site_id, role_id, starts_at, ends_at, headcount,
    worker_rate, client_rate, status, created_by
  ) values (
    p_site_id, p_role_id, p_starts_at, p_ends_at, p_headcount,
    round(p_worker_rate, 2), round(p_client_rate, 2), 'draft', auth.uid()
  ) returning id into v_shift_id;

  v_margin_pct := case when p_client_rate > 0
    then round(((p_client_rate - p_worker_rate) / p_client_rate) * 100, 2)
    else null end;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'shift.draft_created', 'shift', v_shift_id,
    jsonb_build_object(
      'site_id', p_site_id,
      'role_id', p_role_id,
      'headcount', p_headcount,
      'starts_at', p_starts_at,
      'ends_at', p_ends_at,
      'margin_below_10pct', coalesce(v_margin_pct < 10, true)
    )
  );

  return v_shift_id;
end;
$$;

revoke all on function public.create_shift_draft(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric) from public;
grant execute on function public.create_shift_draft(uuid,uuid,timestamptz,timestamptz,integer,numeric,numeric) to authenticated;

create or replace function public.open_shift(p_shift_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_site_active boolean;
  v_client_active boolean;
  v_role_active boolean;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;

  select * into v_shift
  from public.shifts
  where id = p_shift_id
  for update;

  if v_shift.id is null then raise exception 'shift not found'; end if;
  if v_shift.status <> 'draft' then raise exception 'only draft shifts can be opened'; end if;
  if v_shift.starts_at <= now() then raise exception 'cannot open a shift that has started'; end if;

  select s.active, c.active into v_site_active, v_client_active
  from public.sites s join public.clients c on c.id=s.client_id
  where s.id=v_shift.site_id;
  select active into v_role_active from public.roles where id=v_shift.role_id;

  if not coalesce(v_site_active,false) or not coalesce(v_client_active,false) then
    raise exception 'site or client is inactive';
  end if;
  if not coalesce(v_role_active,false) then raise exception 'role is inactive'; end if;

  update public.shifts set status='open' where id=p_shift_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'shift.opened', 'shift', p_shift_id,
    jsonb_build_object('headcount', v_shift.headcount, 'starts_at', v_shift.starts_at, 'ends_at', v_shift.ends_at));

  return p_shift_id;
end;
$$;

revoke all on function public.open_shift(uuid) from public;
grant execute on function public.open_shift(uuid) to authenticated;

-- No direct authenticated writes to clients/sites/roles/shifts are granted.
-- Workers discover open shifts through get_available_shifts() and accept them through secure RPCs.
