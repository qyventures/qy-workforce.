-- QY Workforce: auditable worker case notes and operational status history.
-- Notes are internal operational records only. They must not contain raw identity documents,
-- medical details, biometric data, secrets or other unnecessary sensitive content.

create table if not exists public.worker_case_notes (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.worker_profiles(user_id) on delete restrict,
  note_type text not null check (note_type in ('general','readiness','attendance','training','client_feedback','conduct','follow_up')),
  visibility text not null default 'ops' check (visibility in ('ops','admin_only')),
  note text not null,
  status text not null default 'active' check (status in ('active','resolved','voided')),
  created_by uuid not null references public.profiles(id),
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(trim(note)) between 1 and 2000),
  check (resolution_note is null or char_length(resolution_note) <= 1000)
);

create index if not exists worker_case_notes_worker_status_idx
  on public.worker_case_notes(worker_id, status, created_at desc);

alter table public.worker_case_notes enable row level security;
revoke insert, update, delete on public.worker_case_notes from anon, authenticated;

create policy "ops read worker case notes"
  on public.worker_case_notes for select
  using (
    public.is_ops()
    and (visibility = 'ops' or (visibility = 'admin_only' and exists (
      select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'
    )))
  );

create or replace function public.add_worker_case_note(
  p_worker_id uuid,
  p_note_type text,
  p_note text,
  p_visibility text default 'ops'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_worker_id = auth.uid() then raise exception 'self-review not permitted'; end if;
  if p_note_type not in ('general','readiness','attendance','training','client_feedback','conduct','follow_up') then
    raise exception 'invalid note type';
  end if;
  if p_visibility not in ('ops','admin_only') then raise exception 'invalid visibility'; end if;
  if nullif(trim(coalesce(p_note,'')),'') is null or char_length(trim(p_note)) > 2000 then
    raise exception 'note required and must be <= 2000 characters';
  end if;
  if not exists(select 1 from public.worker_profiles where user_id=p_worker_id) then raise exception 'worker not found'; end if;

  select role into v_role from public.profiles where id=auth.uid();
  if p_visibility='admin_only' and v_role <> 'admin' then raise exception 'admin-only note requires admin role'; end if;

  insert into public.worker_case_notes(worker_id,note_type,visibility,note,created_by)
  values(p_worker_id,p_note_type,p_visibility,trim(p_note),auth.uid()) returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_case_note.created','worker_case_note',v_id,
    jsonb_build_object('worker_id',p_worker_id,'note_type',p_note_type,'visibility',p_visibility));
  return v_id;
end $$;
revoke all on function public.add_worker_case_note(uuid,text,text,text) from public;
grant execute on function public.add_worker_case_note(uuid,text,text,text) to authenticated;

create or replace function public.resolve_worker_case_note(
  p_note_id uuid,
  p_resolution_note text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_worker uuid;
  v_visibility text;
  v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if nullif(trim(coalesce(p_resolution_note,'')),'') is null or char_length(trim(p_resolution_note)) > 1000 then
    raise exception 'resolution note required and must be <= 1000 characters';
  end if;

  select worker_id, visibility into v_worker, v_visibility
    from public.worker_case_notes where id=p_note_id and status='active' for update;
  if not found then raise exception 'active note not found'; end if;
  if v_worker=auth.uid() then raise exception 'self-review not permitted'; end if;

  select role into v_role from public.profiles where id=auth.uid();
  if v_visibility='admin_only' and v_role <> 'admin' then raise exception 'not authorised'; end if;

  update public.worker_case_notes
     set status='resolved', resolved_by=auth.uid(), resolved_at=now(),
         resolution_note=trim(p_resolution_note), updated_at=now()
   where id=p_note_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'worker_case_note.resolved','worker_case_note',p_note_id,
    jsonb_build_object('worker_id',v_worker));
end $$;
revoke all on function public.resolve_worker_case_note(uuid,text) from public;
grant execute on function public.resolve_worker_case_note(uuid,text) to authenticated;

create or replace view public.worker_status_history
with (security_invoker = true) as
select
  ae.entity_id as worker_id,
  ae.created_at,
  ae.actor_id,
  ae.metadata->>'from_status' as from_status,
  ae.metadata->>'to_status' as to_status,
  ae.metadata->>'reason' as reason
from public.audit_events ae
where ae.entity_type='worker_profile' and ae.action='worker_status.changed';

revoke all on public.worker_status_history from public, anon;
grant select on public.worker_status_history to authenticated;

comment on table public.worker_case_notes is
  'Internal auditable worker operational notes. Do not store raw identity, medical, biometric or secret material.';
comment on view public.worker_status_history is
  'RLS-preserving status change history derived from immutable audit events.';
