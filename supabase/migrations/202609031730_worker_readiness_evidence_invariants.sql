-- QY Workforce: keep vetting and training evidence coherent.
-- NOT VALID preserves legacy staging rows while enforcing every new write/update.

alter table public.worker_vetting
  drop constraint if exists worker_vetting_review_evidence_consistency;
alter table public.worker_vetting
  add constraint worker_vetting_review_evidence_consistency
  check (
    (status = 'pending'
      and reviewed_by is null
      and reviewed_at is null
      and notes_redacted is null)
    or (status = 'passed'
      and reviewed_by is not null
      and reviewed_at is not null)
    or (status in ('failed','manual_review')
      and reviewed_by is not null
      and reviewed_at is not null
      and nullif(trim(notes_redacted), '') is not null
      and char_length(notes_redacted) <= 2000)
  ) not valid;

alter table public.worker_training
  drop constraint if exists worker_training_completion_evidence_consistency;
alter table public.worker_training
  add constraint worker_training_completion_evidence_consistency
  check (
    (status = 'passed'
      and completed_at is not null
      and verified_by is not null
      and (expires_at is null or expires_at > completed_at))
    or (status <> 'passed'
      and verified_by is null)
  ) not valid;

comment on constraint worker_vetting_review_evidence_consistency
  on public.worker_vetting is
  'Pending vetting has no review evidence; every reviewed outcome has an Ops reviewer and timestamp, and adverse outcomes carry redacted notes.';

comment on constraint worker_training_completion_evidence_consistency
  on public.worker_training is
  'A passed module requires completion and verifier evidence; non-passed rows cannot carry a verifier, and expiry cannot precede completion.';
