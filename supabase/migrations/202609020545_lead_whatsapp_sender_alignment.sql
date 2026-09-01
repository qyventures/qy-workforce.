-- Align the qualification queue default with the approved QY Workforce WhatsApp sender.
-- Historical rows are preserved for auditability; only new queue rows inherit this default.
alter table public.lead_qualification_queue
  alter column sender set default '+6580227816';

comment on column public.lead_qualification_queue.sender is
  'WhatsApp sender intended for qualification dispatch. New records default to the approved QY Workforce number +6580227816; historical rows are retained unchanged.';
