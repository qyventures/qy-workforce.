-- QY Workforce V1: secure payroll export surface and retention controls

alter table public.payroll_batches
  add column if not exists export_format text,
  add column if not exists export_checksum text,
  add column if not exists export_count integer;

create or replace function public.get_payroll_export(p_batch uuid)
returns table (
  batch_id uuid,
  timesheet_id uuid,
  worker_reference uuid,
  worker_name text,
  shift_date date,
  site_name text,
  payable_minutes integer,
  gross_pay numeric,
  currency text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_app_role() not in ('admin','finance') then
    raise exception 'not authorised';
  end if;

  if not exists (
    select 1 from public.payroll_batches pb
    where pb.id = p_batch and pb.status in ('locked','exported')
  ) then raise exception 'payroll batch must be locked before export'; end if;

  return query
  select
    pb.id,
    t.id,
    sa.worker_id,
    coalesce(nullif(trim(p.display_name),''), 'Worker ' || left(sa.worker_id::text, 8)),
    s.starts_at::date,
    si.name,
    t.payable_minutes,
    pbi.gross_pay,
    pbi.currency
  from public.payroll_batch_items pbi
  join public.payroll_batches pb on pb.id = pbi.payroll_batch_id
  join public.timesheets t on t.id = pbi.timesheet_id
  join public.shift_assignments sa on sa.id = t.assignment_id
  join public.profiles p on p.id = sa.worker_id
  join public.shifts s on s.id = sa.shift_id
  join public.sites si on si.id = s.site_id
  where pb.id = p_batch
  order by s.starts_at, p.display_name, sa.worker_id;
end;
$$;

create or replace function public.record_payroll_export(
  p_batch uuid,
  p_format text,
  p_checksum text,
  p_count integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_format not in ('csv','json') then raise exception 'unsupported format'; end if;
  if p_count < 0 then raise exception 'invalid export count'; end if;
  if nullif(trim(p_checksum),'') is null then raise exception 'checksum required'; end if;

  update public.payroll_batches
  set status = 'exported',
      exported_at = coalesce(exported_at, now()),
      export_format = p_format,
      export_checksum = left(trim(p_checksum),256),
      export_count = p_count
  where id = p_batch and status in ('locked','exported');
  if not found then raise exception 'batch not found or not locked'; end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payroll_export.recorded', 'payroll_batch', p_batch,
    jsonb_build_object('format', p_format, 'count', p_count, 'checksum', left(trim(p_checksum),256))
  );
end;
$$;

revoke all on function public.get_payroll_export(uuid) from public;
revoke all on function public.record_payroll_export(uuid,text,text,integer) from public;
grant execute on function public.get_payroll_export(uuid) to authenticated;
grant execute on function public.record_payroll_export(uuid,text,text,integer) to authenticated;

create table if not exists public.data_retention_policies (
  data_class text primary key,
  retention_days integer not null check (retention_days between 1 and 3650),
  rationale text not null,
  updated_at timestamptz not null default now()
);

insert into public.data_retention_policies(data_class, retention_days, rationale) values
  ('public_leads', 365, 'Retain only as long as reasonably needed for sales/recruitment follow-up'),
  ('location_events', 730, 'Attendance dispute and payroll audit support; review before production launch'),
  ('audit_events', 2555, 'Security and operational accountability; review against statutory obligations'),
  ('identity_verifications', 730, 'Retain verification outcome and minimal evidence metadata; do not retain unnecessary raw identity payloads')
on conflict (data_class) do nothing;

alter table public.data_retention_policies enable row level security;
create policy retention_admin_read on public.data_retention_policies
for select using (public.current_app_role() in ('admin','auditor'));
create policy retention_admin_write on public.data_retention_policies
for all using (public.current_app_role()='admin') with check (public.current_app_role()='admin');
