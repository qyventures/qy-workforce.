-- QY Workforce: controlled supervisor-to-site authorization lifecycle.
-- Supervisors may read/review only assigned sites. Assignment changes are therefore
-- privileged authorization changes and must be auditable rather than direct table writes.

revoke insert, update, delete on public.supervisor_sites from authenticated;

drop policy if exists "ops manage supervisor sites" on public.supervisor_sites;

create policy "privileged read supervisor sites" on public.supervisor_sites
for select to authenticated
using (
  public.is_privileged()
  or supervisor_id = auth.uid()
);

create or replace function public.assign_supervisor_site(
  p_supervisor_id uuid,
  p_site_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supervisor_role public.user_role;
  v_site_active boolean;
  v_reason text;
begin
  if not public.is_ops() then
    raise exception 'not authorised';
  end if;

  v_reason := nullif(trim(p_reason), '');
  if v_reason is null then
    raise exception 'assignment reason required';
  end if;
  v_reason := left(v_reason, 500);

  select role into v_supervisor_role
  from public.profiles
  where id = p_supervisor_id;

  if v_supervisor_role is null then
    raise exception 'supervisor not found';
  end if;
  if v_supervisor_role <> 'supervisor' then
    raise exception 'target user is not a supervisor';
  end if;

  select active into v_site_active
  from public.sites
  where id = p_site_id
  for update;

  if v_site_active is null then
    raise exception 'site not found';
  end if;
  if not v_site_active then
    raise exception 'cannot assign inactive site';
  end if;

  insert into public.supervisor_sites(supervisor_id, site_id)
  values (p_supervisor_id, p_site_id)
  on conflict (supervisor_id, site_id) do nothing;

  if found then
    insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values (
      auth.uid(),
      'supervisor_site.assigned',
      'site',
      p_site_id,
      jsonb_build_object(
        'supervisor_id', p_supervisor_id,
        'reason', v_reason
      )
    );
  end if;
end;
$$;

create or replace function public.revoke_supervisor_site(
  p_supervisor_id uuid,
  p_site_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
begin
  if not public.is_ops() then
    raise exception 'not authorised';
  end if;

  v_reason := nullif(trim(p_reason), '');
  if v_reason is null then
    raise exception 'revocation reason required';
  end if;
  v_reason := left(v_reason, 500);

  delete from public.supervisor_sites
  where supervisor_id = p_supervisor_id
    and site_id = p_site_id;

  if not found then
    raise exception 'supervisor site assignment not found';
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'supervisor_site.revoked',
    'site',
    p_site_id,
    jsonb_build_object(
      'supervisor_id', p_supervisor_id,
      'reason', v_reason
    )
  );
end;
$$;

revoke all on function public.assign_supervisor_site(uuid,uuid,text) from public;
revoke all on function public.revoke_supervisor_site(uuid,uuid,text) from public;
grant execute on function public.assign_supervisor_site(uuid,uuid,text) to authenticated;
grant execute on function public.revoke_supervisor_site(uuid,uuid,text) to authenticated;
