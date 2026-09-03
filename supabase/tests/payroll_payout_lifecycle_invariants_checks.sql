-- Structural regression checks for payout lifecycle evidence and payment boundary.

do $$
declare v_def text;
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.worker_payouts'::regclass
      and conname='worker_payouts_status_evidence_consistency'
      and not convalidated
  ) then raise exception 'payout lifecycle evidence constraint must be a NOT VALID forward-write constraint'; end if;

  select pg_get_functiondef('public.set_worker_payout_status(uuid,text,text,text,text)'::regprocedure) into v_def;
  if position('for update' in lower(v_def)) = 0
     or position('v_payout.status=''approved'' and p_status in (''processing'',''cancelled'')' in lower(v_def)) = 0
     or position('payout preparer cannot approve the same payout' in lower(v_def)) = 0
     or position('paid payout requires external reference' in lower(v_def)) = 0
     or position('has_external_reference' in lower(v_def)) = 0 then
    raise exception 'payout status RPC must lock rows, require processing and gate paid evidence';
  end if;

  if has_function_privilege('anon','public.set_worker_payout_status(uuid,text,text,text,text)','EXECUTE') then
    raise exception 'anonymous users must not mutate payout status';
  end if;
end $$;
