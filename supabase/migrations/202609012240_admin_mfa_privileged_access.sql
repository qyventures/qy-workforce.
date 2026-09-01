-- QY Workforce: MFA-gated privileged access changes with separation of duties.
-- Admin role changes require an AAL2 session, a distinct approving admin, and an audit trail.

create table if not exists public.privileged_access_change_requests (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null references public.profiles(id) on delete restrict,
  current_role public.user_role not null,
  requested_role public.user_role not null,
  reason text not null check (char_length(reason) between 5 and 1000),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by uuid not null references public.profiles(id),
  requested_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text check (review_note is null or char_length(review_note) <= 1000),
  applied_at timestamptz,
  check (current_role <> requested_role)
);

create index if not exists privileged_access_change_queue_idx
  on public.privileged_access_change_requests(status, requested_at desc);
create index if not exists privileged_access_change_target_idx
  on public.privileged_access_change_requests(target_user_id, requested_at desc);

alter table public.privileged_access_change_requests enable row level security;
revoke insert, update, delete on public.privileged_access_change_requests from anon, authenticated;

create or replace function public.is_admin_mfa()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select auth.uid() is not null
     and coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
     and exists (
       select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'admin'::public.user_role
     );
$$;

revoke all on function public.is_admin_mfa() from public;
grant execute on function public.is_admin_mfa() to authenticated;

create policy "mfa admins read privileged access queue"
on public.privileged_access_change_requests
for select using (public.is_admin_mfa());

create or replace function public.admin_request_privileged_access_change(
  p_target_user_id uuid,
  p_requested_role text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_current public.user_role;
  v_requested public.user_role;
begin
  if not public.is_admin_mfa() then
    raise exception 'admin MFA (AAL2) required';
  end if;
  if p_target_user_id is null then raise exception 'target user required'; end if;
  if p_target_user_id = auth.uid() then raise exception 'self role changes are not permitted'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null or char_length(trim(p_reason)) < 5 then
    raise exception 'reason required';
  end if;

  begin
    v_requested := p_requested_role::public.user_role;
  exception when invalid_text_representation then
    raise exception 'invalid requested role';
  end;

  select role into v_current from public.profiles where id=p_target_user_id for update;
  if v_current is null then raise exception 'target user not found'; end if;
  if v_current = v_requested then raise exception 'requested role matches current role'; end if;
  if exists (
    select 1 from public.privileged_access_change_requests
     where target_user_id=p_target_user_id and status='pending'
  ) then raise exception 'pending role change already exists for target'; end if;

  insert into public.privileged_access_change_requests(
    target_user_id,current_role,requested_role,reason,requested_by
  ) values (
    p_target_user_id,v_current,v_requested,trim(p_reason),auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.privileged_access_change_requested','privileged_access_change_request',v_id,
    jsonb_build_object('target_user_id',p_target_user_id,'from_role',v_current::text,'to_role',v_requested::text));

  return v_id;
end $$;

create or replace function public.admin_review_privileged_access_change(
  p_request_id uuid,
  p_decision text,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_req public.privileged_access_change_requests%rowtype;
  v_live_role public.user_role;
  v_admin_count integer;
begin
  if not public.is_admin_mfa() then
    raise exception 'admin MFA (AAL2) required';
  end if;
  if p_decision not in ('approve','reject') then raise exception 'invalid decision'; end if;
  if p_note is not null and char_length(p_note)>1000 then raise exception 'note too long'; end if;

  select * into v_req from public.privileged_access_change_requests where id=p_request_id for update;
  if not found then raise exception 'request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'request is not pending'; end if;
  if v_req.requested_by = auth.uid() then raise exception 'requester cannot approve or reject own request'; end if;

  select role into v_live_role from public.profiles where id=v_req.target_user_id for update;
  if v_live_role is null then raise exception 'target user not found'; end if;
  if v_live_role <> v_req.current_role then raise exception 'target role changed since request; create a new request'; end if;

  if p_decision='approve' then
    if v_live_role='admin'::public.user_role and v_req.requested_role <> 'admin'::public.user_role then
      select count(*) into v_admin_count from public.profiles where role='admin'::public.user_role;
      if v_admin_count <= 1 then raise exception 'cannot remove the last admin'; end if;
    end if;

    update public.profiles
       set role=v_req.requested_role, updated_at=now()
     where id=v_req.target_user_id;

    update public.privileged_access_change_requests
       set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),''),applied_at=now()
     where id=p_request_id;

    insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'admin.privileged_access_change_approved','privileged_access_change_request',p_request_id,
      jsonb_build_object('target_user_id',v_req.target_user_id,'from_role',v_req.current_role::text,'to_role',v_req.requested_role::text));
  else
    update public.privileged_access_change_requests
       set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'')
     where id=p_request_id;

    insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'admin.privileged_access_change_rejected','privileged_access_change_request',p_request_id,
      jsonb_build_object('target_user_id',v_req.target_user_id));
  end if;
end $$;

create or replace function public.admin_cancel_own_privileged_access_change(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin_mfa() then raise exception 'admin MFA (AAL2) required'; end if;
  update public.privileged_access_change_requests
     set status='cancelled', reviewed_at=now(), review_note='cancelled by requester'
   where id=p_request_id and status='pending' and requested_by=auth.uid();
  if not found then raise exception 'pending request not found or not owned by requester'; end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id)
  values(auth.uid(),'admin.privileged_access_change_cancelled','privileged_access_change_request',p_request_id);
end $$;

revoke all on function public.admin_request_privileged_access_change(uuid,text,text) from public;
revoke all on function public.admin_review_privileged_access_change(uuid,text,text) from public;
revoke all on function public.admin_cancel_own_privileged_access_change(uuid) from public;
grant execute on function public.admin_request_privileged_access_change(uuid,text,text) to authenticated;
grant execute on function public.admin_review_privileged_access_change(uuid,text,text) to authenticated;
grant execute on function public.admin_cancel_own_privileged_access_change(uuid) to authenticated;
