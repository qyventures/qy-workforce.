-- QY Workforce: keep payout approval and payment execution states auditable.
-- NOT VALID preserves legacy staging rows while enforcing all new writes.

alter table public.worker_payouts
  drop constraint if exists worker_payouts_status_evidence_consistency;
alter table public.worker_payouts
  add constraint worker_payouts_status_evidence_consistency
  check (
    (status = 'pending' and approved_by is null and approved_at is null and paid_at is null)
    or (status in ('approved','processing') and approved_by is not null and approved_at is not null and paid_at is null)
    or (status = 'paid' and approved_by is not null and approved_at is not null and paid_at is not null)
    or (status in ('failed','cancelled') and paid_at is null)
  ) not valid;

create or replace function public.set_worker_payout_status(
  p_payout uuid,
  p_status text,
  p_external_reference text default null,
  p_method text default null,
  p_exception_reason text default null
) returns void language plpgsql security definer set search_path = public
as $$
declare
  v_payout public.worker_payouts%rowtype;
  v_method text;
  v_external_reference text;
  v_exception_reason text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if public.current_app_role() not in ('admin','finance') then raise exception 'not authorised'; end if;
  if p_status not in ('approved','processing','paid','failed','cancelled') then raise exception 'invalid payout status'; end if;

  select * into v_payout from public.worker_payouts where id=p_payout for update;
  if not found then raise exception 'payout not found'; end if;
  if p_status='approved' and v_payout.prepared_by=auth.uid() then raise exception 'payout preparer cannot approve the same payout'; end if;
  if not ((v_payout.status='pending' and p_status in ('approved','cancelled')) or
          (v_payout.status='approved' and p_status in ('processing','cancelled')) or
          (v_payout.status='processing' and p_status in ('paid','failed')) or
          (v_payout.status='failed' and p_status in ('processing','cancelled'))) then
    raise exception 'invalid payout transition';
  end if;

  v_method := coalesce(p_method, v_payout.method);
  v_external_reference := coalesce(nullif(trim(p_external_reference),''), v_payout.external_reference);
  v_exception_reason := coalesce(nullif(trim(p_exception_reason),''), v_payout.exception_reason);
  if v_method not in ('bank','cash_exception','other') then raise exception 'invalid payout method'; end if;
  if v_method='cash_exception' and char_length(coalesce(v_exception_reason,'')) < 5 then
    raise exception 'cash exception requires reason';
  end if;
  if p_status='paid' and v_external_reference is null then
    raise exception 'paid payout requires external reference';
  end if;
  if v_external_reference is not null and char_length(v_external_reference) > 200 then
    raise exception 'external reference too long';
  end if;

  update public.worker_payouts set
    status=p_status,
    method=v_method,
    exception_reason=case when v_method='cash_exception' then v_exception_reason else exception_reason end,
    external_reference=v_external_reference,
    approved_by=case when p_status='approved' then auth.uid() else approved_by end,
    approved_at=case when p_status='approved' then now() else approved_at end,
    paid_at=case when p_status='paid' then now() else paid_at end,
    updated_at=now()
  where id=p_payout;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_payout.status_changed','worker_payout',p_payout,
         jsonb_build_object('from',v_payout.status,'to',p_status,'method',v_method,
                            'has_external_reference',v_external_reference is not null));
end; $$;

revoke all on function public.set_worker_payout_status(uuid,text,text,text,text) from public;
grant execute on function public.set_worker_payout_status(uuid,text,text,text,text) to authenticated;

comment on table public.worker_payouts is
'Controlled payout ledger. Approval evidence is required before processing; payment evidence is required before paid, and paid transitions require an external reference.';
