-- QY Workforce V1: payroll-ready controls and auditable export workflow

create table if not exists public.payroll_batches (
  id uuid primary key default gen_random_uuid(),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','locked','exported','cancelled')),
  created_by uuid not null references auth.users(id),
  locked_at timestamptz,
  exported_at timestamptz,
  created_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create table if not exists public.payroll_batch_items (
  id uuid primary key default gen_random_uuid(),
  payroll_batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  timesheet_id uuid not null references public.timesheets(id),
  gross_pay numeric(12,2) not null check (gross_pay >= 0),
  currency text not null default 'SGD',
  created_at timestamptz not null default now(),
  unique (payroll_batch_id, timesheet_id)
);

alter table public.payroll_batches enable row level security;
alter table public.payroll_batch_items enable row level security;

create policy payroll_batches_finance_read on public.payroll_batches
for select using (public.has_app_role(array['admin','ops','finance','auditor']));

create policy payroll_batches_finance_write on public.payroll_batches
for all using (public.has_app_role(array['admin','finance']))
with check (public.has_app_role(array['admin','finance']));

create policy payroll_items_finance_read on public.payroll_batch_items
for select using (public.has_app_role(array['admin','ops','finance','auditor']));

create policy payroll_items_finance_write on public.payroll_batch_items
for all using (public.has_app_role(array['admin','finance']))
with check (public.has_app_role(array['admin','finance']));

create or replace function public.create_payroll_batch(p_start date, p_end date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch uuid;
begin
  if not public.has_app_role(array['admin','finance']) then
    raise exception 'not authorised';
  end if;

  if p_end < p_start then
    raise exception 'invalid pay period';
  end if;

  insert into public.payroll_batches(period_start, period_end, created_by)
  values (p_start, p_end, auth.uid()) returning id into v_batch;

  insert into public.payroll_batch_items(payroll_batch_id, timesheet_id, gross_pay)
  select v_batch, t.id,
         round((greatest(coalesce(t.payable_minutes,0),0)::numeric / 60.0) * coalesce(s.worker_rate,0), 2)
  from public.timesheets t
  join public.shift_assignments sa on sa.id = t.shift_assignment_id
  join public.shifts s on s.id = sa.shift_id
  where t.status = 'approved'
    and s.starts_at::date between p_start and p_end
    and not exists (
      select 1 from public.payroll_batch_items pbi
      join public.payroll_batches pb on pb.id = pbi.payroll_batch_id
      where pbi.timesheet_id = t.id and pb.status in ('locked','exported')
    );

  insert into public.audit_events(actor_user_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'payroll_batch_created', 'payroll_batch', v_batch, jsonb_build_object('period_start',p_start,'period_end',p_end));

  return v_batch;
end;
$$;

create or replace function public.lock_payroll_batch(p_batch uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_app_role(array['admin','finance']) then raise exception 'not authorised'; end if;
  update public.payroll_batches set status='locked', locked_at=now()
  where id=p_batch and status='draft';
  if not found then raise exception 'batch not found or not draft'; end if;
  insert into public.audit_events(actor_user_id, action, entity_type, entity_id)
  values (auth.uid(),'payroll_batch_locked','payroll_batch',p_batch);
end;
$$;

create or replace function public.mark_payroll_batch_exported(p_batch uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_app_role(array['admin','finance']) then raise exception 'not authorised'; end if;
  update public.payroll_batches set status='exported', exported_at=now()
  where id=p_batch and status='locked';
  if not found then raise exception 'batch not found or not locked'; end if;
  insert into public.audit_events(actor_user_id, action, entity_type, entity_id)
  values (auth.uid(),'payroll_batch_exported','payroll_batch',p_batch);
end;
$$;

grant execute on function public.create_payroll_batch(date,date) to authenticated;
grant execute on function public.lock_payroll_batch(uuid) to authenticated;
grant execute on function public.mark_payroll_batch_exported(uuid) to authenticated;
