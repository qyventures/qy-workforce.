-- Durable client billing ledger built from approved/payroll-ready timesheets.
-- Financial snapshots are immutable; only controlled billing-state metadata may transition.

create table public.client_billing_items (
  id uuid primary key default gen_random_uuid(),
  timesheet_id uuid not null unique references public.timesheets(id) on delete restrict,
  assignment_id uuid not null references public.shift_assignments(id) on delete restrict,
  shift_id uuid not null references public.shifts(id) on delete restrict,
  site_id uuid not null references public.sites(id) on delete restrict,
  client_id uuid not null references public.clients(id) on delete restrict,
  service_date date not null,
  payable_minutes integer not null check (payable_minutes >= 0),
  worker_amount numeric(12,2) not null default 0,
  client_amount numeric(12,2) not null check (client_amount >= 0),
  gross_margin numeric(12,2) generated always as (client_amount-worker_amount) stored,
  billing_status text not null default 'pending'
    check (billing_status in ('pending','invoice_ready','invoiced','paid','disputed')),
  invoice_reference text,
  reconciled_note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  invoice_ready_at timestamptz,
  invoiced_at timestamptz,
  paid_at timestamptz,
  disputed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index client_billing_items_client_status_idx
  on public.client_billing_items(client_id,billing_status,service_date);
create index client_billing_items_site_date_idx
  on public.client_billing_items(site_id,service_date);

alter table public.client_billing_items enable row level security;

create policy "privileged read client billing" on public.client_billing_items
for select using (public.current_app_role() in ('ops_manager','finance','admin','auditor'));

-- No direct authenticated mutations. All writes flow through the RPCs below.
revoke insert, update, delete on public.client_billing_items from anon, authenticated;

create or replace function public.protect_client_billing_snapshot()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='DELETE' then
    raise exception 'client billing records are append-only';
  end if;

  if new.timesheet_id is distinct from old.timesheet_id
     or new.assignment_id is distinct from old.assignment_id
     or new.shift_id is distinct from old.shift_id
     or new.site_id is distinct from old.site_id
     or new.client_id is distinct from old.client_id
     or new.service_date is distinct from old.service_date
     or new.payable_minutes is distinct from old.payable_minutes
     or new.worker_amount is distinct from old.worker_amount
     or new.client_amount is distinct from old.client_amount
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'client billing financial snapshot is immutable';
  end if;
  return new;
end;
$$;

create trigger protect_client_billing_snapshot_trg
before update or delete on public.client_billing_items
for each row execute function public.protect_client_billing_snapshot();

create or replace function public.sync_client_billing_items(p_start date, p_end date)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer;
begin
  if public.current_app_role() not in ('finance','admin') then
    raise exception 'not authorised';
  end if;
  if p_start is null or p_end is null or p_end < p_start or p_end > p_start + 366 then
    raise exception 'invalid billing period';
  end if;

  insert into public.client_billing_items(
    timesheet_id,assignment_id,shift_id,site_id,client_id,service_date,
    payable_minutes,worker_amount,client_amount,created_by
  )
  select
    t.id,a.id,sh.id,si.id,c.id,sh.starts_at::date,
    t.payable_minutes,coalesce(t.worker_amount,0),t.client_amount,auth.uid()
  from public.timesheets t
  join public.shift_assignments a on a.id=t.assignment_id
  join public.shifts sh on sh.id=a.shift_id
  join public.sites si on si.id=sh.site_id
  join public.clients c on c.id=si.client_id
  where t.status in ('approved','payroll_ready')
    and t.client_amount is not null
    and t.client_amount >= 0
    and sh.starts_at::date between p_start and p_end
  on conflict (timesheet_id) do nothing;

  get diagnostics v_count = row_count;

  insert into public.audit_events(actor_id,action,entity_type,metadata)
  values(auth.uid(),'client_billing.synced','client_billing_item',
    jsonb_build_object('period_start',p_start,'period_end',p_end,'items_created',v_count));

  return v_count;
end;
$$;
revoke all on function public.sync_client_billing_items(date,date) from public;
grant execute on function public.sync_client_billing_items(date,date) to authenticated;

create or replace function public.transition_client_billing_item(
  p_item_id uuid,
  p_status text,
  p_invoice_reference text default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_current text;
  v_invoice text;
begin
  if public.current_app_role() not in ('finance','admin') then
    raise exception 'not authorised';
  end if;
  if p_status not in ('invoice_ready','invoiced','paid','disputed') then
    raise exception 'unsupported billing status';
  end if;

  select billing_status,invoice_reference into v_current,v_invoice
  from public.client_billing_items
  where id=p_item_id
  for update;
  if v_current is null then raise exception 'billing item not found'; end if;

  if not (
    (v_current='pending' and p_status in ('invoice_ready','disputed'))
    or (v_current='invoice_ready' and p_status in ('invoiced','disputed'))
    or (v_current='invoiced' and p_status in ('paid','disputed'))
    or (v_current='disputed' and p_status='invoice_ready')
  ) then
    raise exception 'invalid billing transition from % to %',v_current,p_status;
  end if;

  if p_status in ('invoiced','paid')
     and nullif(trim(coalesce(p_invoice_reference,v_invoice,'')),'') is null then
    raise exception 'invoice reference required';
  end if;

  update public.client_billing_items
  set billing_status=p_status,
      invoice_reference=case
        when p_invoice_reference is not null then left(trim(p_invoice_reference),120)
        else invoice_reference end,
      reconciled_note=case
        when p_note is not null then left(trim(p_note),1000)
        else reconciled_note end,
      invoice_ready_at=case when p_status='invoice_ready' then now() else invoice_ready_at end,
      invoiced_at=case when p_status='invoiced' then now() else invoiced_at end,
      paid_at=case when p_status='paid' then now() else paid_at end,
      disputed_at=case when p_status='disputed' then now() else disputed_at end,
      updated_at=now()
  where id=p_item_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'client_billing.status_changed','client_billing_item',p_item_id,
    jsonb_build_object('from_status',v_current,'to_status',p_status,
                       'invoice_reference_present',nullif(trim(coalesce(p_invoice_reference,v_invoice,'')),'') is not null));
end;
$$;
revoke all on function public.transition_client_billing_item(uuid,text,text,text) from public;
grant execute on function public.transition_client_billing_item(uuid,text,text,text) to authenticated;

create or replace function public.get_client_billing_summary(p_start date, p_end date)
returns table(
  client_id uuid,
  client_name text,
  site_id uuid,
  site_name text,
  billing_status text,
  item_count bigint,
  billable_hours numeric,
  worker_cost numeric,
  client_revenue numeric,
  gross_margin numeric,
  gross_margin_pct numeric
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_app_role() not in ('ops_manager','finance','admin','auditor') then
    raise exception 'not authorised';
  end if;
  if p_start is null or p_end is null or p_end < p_start or p_end > p_start + 366 then
    raise exception 'invalid billing period';
  end if;

  return query
  select b.client_id,c.name,b.site_id,s.name,b.billing_status,
         count(*),round(sum(b.payable_minutes)::numeric/60,2),
         round(sum(b.worker_amount),2),round(sum(b.client_amount),2),round(sum(b.gross_margin),2),
         case when sum(b.client_amount)>0 then round(100*sum(b.gross_margin)/sum(b.client_amount),2) else 0 end
  from public.client_billing_items b
  join public.clients c on c.id=b.client_id
  join public.sites s on s.id=b.site_id
  where b.service_date between p_start and p_end
  group by b.client_id,c.name,b.site_id,s.name,b.billing_status
  order by c.name,s.name,b.billing_status;
end;
$$;
revoke all on function public.get_client_billing_summary(date,date) from public;
grant execute on function public.get_client_billing_summary(date,date) to authenticated;