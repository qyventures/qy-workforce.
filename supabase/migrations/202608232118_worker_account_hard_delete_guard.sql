-- QY Workforce: protect worker operational history from auth/profile cascade deletion.
--
-- public.profiles.id references auth.users(id) ON DELETE CASCADE and worker_profiles
-- cascades further into onboarding evidence. A hard auth-user deletion could therefore
-- erase regulated/operational history outside the privacy-request/retention workflow.
-- Worker erasure must use the existing privacy/retention controls instead.

create or replace function public.prevent_worker_profile_hard_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Explicit database-maintenance escape hatch. This is intentionally not exposed
  -- through an RPC; it must be set by a trusted database operator in the same session
  -- after retention/legal requirements have been satisfied.
  if current_setting('app.allow_worker_hard_delete', true) = 'on' then
    return old;
  end if;

  if exists (
    select 1
    from public.worker_profiles wp
    where wp.user_id = old.id
  ) then
    raise exception using
      errcode = '23503',
      message = 'Worker account hard deletion is blocked; use the privacy erasure and retention workflow';
  end if;

  return old;
end;
$$;

revoke all on function public.prevent_worker_profile_hard_delete() from public;
revoke all on function public.prevent_worker_profile_hard_delete() from anon;
revoke all on function public.prevent_worker_profile_hard_delete() from authenticated;

-- End users must never be able to bypass the worker lifecycle by deleting profile rows.
revoke delete on public.profiles from anon, authenticated;
revoke delete on public.worker_profiles from anon, authenticated;

-- The trigger also catches deletion of public.profiles caused indirectly by
-- auth.users ON DELETE CASCADE.
drop trigger if exists trg_prevent_worker_profile_hard_delete on public.profiles;
create trigger trg_prevent_worker_profile_hard_delete
before delete on public.profiles
for each row
execute function public.prevent_worker_profile_hard_delete();
