-- QY Workforce: make audit history append-only at the database boundary.
-- Audit events are retained as security/legal evidence. Corrections must be represented
-- by a new compensating event rather than rewriting or deleting prior history.

create or replace function public.reject_audit_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'audit events are append-only';
end;
$$;

-- Trigger functions are implementation details; clients never need to invoke this helper.
revoke all on function public.reject_audit_event_mutation() from public;
revoke all on function public.reject_audit_event_mutation() from anon, authenticated;

-- Idempotent recreation makes partial staging deploys safe to repair.
drop trigger if exists audit_events_append_only on public.audit_events;
create trigger audit_events_append_only
before update or delete on public.audit_events
for each row execute function public.reject_audit_event_mutation();

-- Defence in depth. RLS should already expose no ordinary mutation path, but explicit
-- revocation means a future grant/policy change cannot silently make audit history mutable.
revoke update, delete, truncate on public.audit_events from authenticated;
revoke update, delete, truncate on public.audit_events from anon;

comment on function public.reject_audit_event_mutation() is
'Append-only guard for audit_events. Corrections must be recorded as new compensating audit events; existing audit history is never rewritten.';
