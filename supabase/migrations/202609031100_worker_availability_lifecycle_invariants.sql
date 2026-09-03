-- QY Workforce: make availability-exception lifecycle evidence internally consistent.
-- NOT VALID preserves compatibility with any pre-existing staging rows while
-- enforcing the lifecycle contract for every new row and future update.

alter table public.worker_availability_exceptions
  drop constraint if exists worker_availability_exceptions_review_evidence_consistency;
alter table public.worker_availability_exceptions
  add constraint worker_availability_exceptions_review_evidence_consistency
  check (
    (status = 'submitted' and reviewed_by is null and reviewed_at is null and cancelled_at is null)
    or (status in ('approved','rejected') and reviewed_by is not null and reviewed_at is not null and cancelled_at is null)
    or (status = 'cancelled' and cancelled_at is not null)
  ) not valid;

alter table public.worker_availability_exceptions
  drop constraint if exists worker_availability_exceptions_review_pair_consistency;
alter table public.worker_availability_exceptions
  add constraint worker_availability_exceptions_review_pair_consistency
  check ((reviewed_by is null) = (reviewed_at is null)) not valid;

alter table public.worker_availability_exceptions
  drop constraint if exists worker_availability_exceptions_cancelled_status_consistency;
alter table public.worker_availability_exceptions
  add constraint worker_availability_exceptions_cancelled_status_consistency
  check (cancelled_at is null or status = 'cancelled') not valid;

comment on table public.worker_availability_exceptions is
'Worker availability, leave, medical leave and other exception records. Approved records require reviewer evidence; cancellation is explicitly timestamped. Supporting documents reference private worker document metadata; no raw medical content is stored here.';
