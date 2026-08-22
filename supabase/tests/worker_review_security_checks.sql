-- QY Workforce worker-review security invariants.
-- Run in staging/CI after migrations.

begin;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'get_worker_review_queue','review_worker_role','review_worker_vetting',
      'review_worker_training','set_worker_operational_status'
    ) and not p.prosecdef
  ) then raise exception 'worker review RPCs must remain SECURITY DEFINER'; end if;

  if has_table_privilege('authenticated','public.worker_profiles','UPDATE') then
    raise exception 'worker profile operational mutation must be RPC-only';
  end if;

  if has_table_privilege('authenticated','public.worker_roles','INSERT')
     or has_table_privilege('authenticated','public.worker_roles','UPDATE')
     or has_table_privilege('authenticated','public.worker_roles','DELETE') then
    raise exception 'worker role review must be RPC-only';
  end if;

  if has_table_privilege('authenticated','public.worker_vetting','INSERT')
     or has_table_privilege('authenticated','public.worker_vetting','UPDATE')
     or has_table_privilege('authenticated','public.worker_vetting','DELETE') then
    raise exception 'worker vetting review must be RPC-only';
  end if;

  if has_table_privilege('authenticated','public.worker_training','INSERT')
     or has_table_privilege('authenticated','public.worker_training','UPDATE')
     or has_table_privilege('authenticated','public.worker_training','DELETE') then
    raise exception 'worker training review must be RPC-only';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_worker_role'
      and pg_get_functiondef(p.oid) ilike '%for update%'
      and pg_get_functiondef(p.oid) ilike '%self-review not permitted%'
      and pg_get_functiondef(p.oid) ilike '%worker_role_interests%'
      and pg_get_functiondef(p.oid) ilike '%on conflict%'
  ) then raise exception 'role review must lock a declared interest, prevent self-review and upsert approval'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_worker_training'
      and pg_get_functiondef(p.oid) ilike '%for update of wt%'
      and pg_get_functiondef(p.oid) ilike '%self-review not permitted%'
      and pg_get_functiondef(p.oid) ilike '%make_interval%'
      and pg_get_functiondef(p.oid) ilike '%worker_training.reviewed%'
  ) then raise exception 'training review must lock, prevent self-review, calculate expiry and audit'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_worker_vetting'
      and pg_get_functiondef(p.oid) ilike '%for update%'
      and pg_get_functiondef(p.oid) ilike '%self-review not permitted%'
      and pg_get_functiondef(p.oid) ilike '%notes_redacted%'
  ) then raise exception 'vetting review must lock, prevent self-review and use redacted notes'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='set_worker_operational_status'
      and pg_get_functiondef(p.oid) ilike '%for update%'
      and pg_get_functiondef(p.oid) ilike '%worker_has_deployment_prerequisites%'
      and pg_get_functiondef(p.oid) ilike '%reason required for suspended/rejected status%'
  ) then raise exception 'operational status gate must lock, enforce live prerequisites and require adverse-action reasons'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_worker_review_queue'
      and pg_get_functiondef(p.oid) ilike '%W-%'
      and pg_get_functiondef(p.oid) not ilike '%display_name%'
      and pg_get_functiondef(p.oid) not ilike '%phone%'
  ) then raise exception 'worker review queue must remain pseudonymous and operationally minimal'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='get_worker_review_queue'
      and pg_get_functiondef(p.oid) ilike '%worker_role_interests%'
      and pg_get_functiondef(p.oid) ilike '%not exists%worker_roles%'
  ) then raise exception 'pending role reviews must derive from declared worker interests'; end if;
end $$;

rollback;
