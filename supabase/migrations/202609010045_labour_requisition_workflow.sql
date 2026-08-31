-- QY Workforce: auditable labour requisition workflow.
-- Captures client demand before it becomes an operational shift and keeps writes behind Ops RPCs.

create table if not exists public.labour_requisitions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id),
  site_id uuid not null references public.sites(id),
  role_id uuid not null references public.roles(id),
  requested_headcount integer not null check (requested_headcount between 1 and 500),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  worker_rate numeric(10,2) not null check (worker_rate between 0 and 1000),
  client_rate numeric(10,2) not null check (client_rate between 0 and 1000),
  requirements text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','converted','cancelled')),
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  decision_reason text,
  converted_shift_id uuid references public.shifts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (requirements is null or char_length(requirements) <= 2000),
  check (decision_reason is null or char_length(decision_reason) <= 1000)
);

create index if not exists labour_requisitions_status_start_idx
  on public.labour_requisitions(status, starts_at);
create index if not exists labour_requisitions_client_idx
  on public.labour_requisitions(client_id, created_at desc);

alter table public.labour_requisitions enable row level security;
revoke insert, update, delete on table public.labour_requisitions from anon, authenticated;

create policy "privileged read labour requisitions" on public.labour_requisitions
for select using (public.is_privileged());

create or replace function public.create_labour_requisition(
  p_site_id uuid,
  p_role_id uuid,
  p_requested_headcount integer,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_worker_rate numeric,
  p_client_rate numeric,
  p_requirements text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_client_id uuid;
  v_site_active boolean;
  v_client_active boolean;
  v_role_active boolean;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_requested_headcount is null or p_requested_headcount < 1 or p_requested_headcount > 500 then
    raise exception 'headcount must be between 1 and 500';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'invalid requisition time range';
  end if;
  if p_starts_at < now() - interval '15 minutes' then raise exception 'start cannot be in the past'; end if;
  if p_ends_at - p_starts_at > interval '24 hours' then raise exception 'duration exceeds 24 hours'; end if;
  if p_worker_rate is null or p_client_rate is null or p_worker_rate < 0 or p_client_rate < 0
     or p_worker_rate > 1000 or p_client_rate > 1000 then
    raise exception 'invalid rates';
  end if;
  if p_requirements is not null and char_length(trim(p_requirements)) > 2000 then
    raise exception 'requirements too long';
  end if;

  select s.client_id, s.active, c.active
    into v_client_id, v_site_active, v_client_active
  from public.sites s
  join public.clients c on c.id = s.client_id
  where s.id = p_site_id;
  if v_client_id is null then raise exception 'site not found'; end if;
  if not v_site_active or not v_client_active then raise exception 'site or client is inactive'; end if;

  select active into v_role_active from public.roles where id = p_role_id;
  if v_role_active is null then raise exception 'role not found'; end if;
  if not v_role_active then raise exception 'role is inactive'; end if;

  insert into public.labour_requisitions(
    client_id, site_id, role_id, requested_headcount, starts_at, ends_at,
    worker_rate, client_rate, requirements, created_by
  ) values (
    v_client_id, p_site_id, p_role_id, p_requested_headcount, p_starts_at, p_ends_at,
    round(p_worker_rate,2), round(p_client_rate,2), nullif(trim(p_requirements),''), auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values(auth.uid(), 'labour_requisition.created', 'labour_requisition', v_id,
    jsonb_build_object('site_id', p_site_id, 'role_id', p_role_id,
      'headcount', p_requested_headcount, 'starts_at', p_starts_at, 'ends_at', p_ends_at));

  return v_id;
end;
$$;

revoke all on function public.create_labour_requisition(uuid,uuid,integer,timestamptz,timestamptz,numeric,numeric,text) from public;
grant execute on function public.create_labour_requisition(uuid,uuid,integer,timestamptz,timestamptz,numeric,numeric,text) to authenticated;

create or replace function public.review_labour_requisition(
  p_requisition_id uuid,
  p_decision text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.labour_requisitions%rowtype;
  v_shift_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_decision not in ('approve','reject','cancel') then raise exception 'invalid decision'; end if;
  if p_reason is null or char_length(trim(p_reason)) < 5 or char_length(trim(p_reason)) > 1000 then
    raise exception 'decision reason must be between 5 and 1000 characters';
  end if;

  select * into v_req from public.labour_requisitions
  where id = p_requisition_id for update;
  if v_req.id is null then raise exception 'requisition not found'; end if;
  if v_req.status <> 'pending' then raise exception 'only pending requisitions can be reviewed'; end if;
  if v_req.starts_at <= now() and p_decision = 'approve' then raise exception 'cannot approve a started requisition'; end if;

  if p_decision = 'approve' then
    insert into public.shifts(site_id, role_id, starts_at, ends_at, headcount,
      worker_rate, client_rate, status, created_by)
    values(v_req.site_id, v_req.role_id, v_req.starts_at, v_req.ends_at, v_req.requested_headcount,
      v_req.worker_rate, v_req.client_rate, 'draft', auth.uid())
    returning id into v_shift_id;

    update public.labour_requisitions
    set status='converted', approved_by=auth.uid(), approved_at=now(),
        decision_reason=trim(p_reason), converted_shift_id=v_shift_id, updated_at=now()
    where id=p_requisition_id;

    insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values(auth.uid(), 'labour_requisition.converted', 'labour_requisition', p_requisition_id,
      jsonb_build_object('shift_id', v_shift_id));
  else
    update public.labour_requisitions
    set status=case when p_decision='reject' then 'rejected' else 'cancelled' end,
        approved_by=auth.uid(), approved_at=now(), decision_reason=trim(p_reason), updated_at=now()
    where id=p_requisition_id;

    insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values(auth.uid(), 'labour_requisition.' || case when p_decision='reject' then 'rejected' else 'cancelled' end,
      'labour_requisition', p_requisition_id, '{}'::jsonb);
  end if;

  return coalesce(v_shift_id, p_requisition_id);
end;
$$;

revoke all on function public.review_labour_requisition(uuid,text,text) from public;
grant execute on function public.review_labour_requisition(uuid,text,text) to authenticated;
