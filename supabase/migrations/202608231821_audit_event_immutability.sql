-- QY Workforce: make audit history append-only at the database boundary.
-- Audit events are a manual/legal-review retention class. They must not be mutable
-- through ordinary SQL even if grants or RLS policies are broadened accidentally.

create or replace function public.reject_audit_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'audit events are append-only';
end;
$$;

revoke all on function public.reject_audit_event_mutation() from public;

-- Idempotent recreation makes this safe if a staging database has a partial prior deploy.
drop trigger if exists audit_events_append_only on public.audit_events;
create trigger audit_events_append_only
before update or delete on public.audit_events
for each row execute function public.reject_audit_event_mutation();

-- Defence in depth: RLS already has no update/delete policy for ordinary users, but
-- explicit revocation prevents accidental direct mutation grants from becoming effective.
revoke update, delete, truncate on public.audit_events from authenticated;
revoke update, delete, truncate on public.audit_events from anon;

comment on function public.reject_audit_event_mutation() is
'Append-only guard for audit_events. Corrections must be represented by a new compensating audit event; existing audit history is never rewritten.';
