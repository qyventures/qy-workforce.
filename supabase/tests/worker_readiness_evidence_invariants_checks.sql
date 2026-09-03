-- Structural regression checks for vetting/training evidence invariants.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.worker_vetting'::regclass
      and conname = 'worker_vetting_review_evidence_consistency'
      and not convalidated
  ) then
    raise exception 'worker vetting evidence constraint must be a NOT VALID forward-write constraint';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.worker_training'::regclass
      and conname = 'worker_training_completion_evidence_consistency'
      and not convalidated
  ) then
    raise exception 'worker training evidence constraint must be a NOT VALID forward-write constraint';
  end if;
end $$;

do $$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid = 'public.worker_vetting'::regclass
    and conname = 'worker_vetting_review_evidence_consistency';
  if v_def is null
     or position('status = ''pending''' in lower(v_def)) = 0
     or position('reviewed_by is null' in lower(v_def)) = 0
     or position('status = ''passed''' in lower(v_def)) = 0
     or position('failed' in lower(v_def)) = 0
     or position('manual_review' in lower(v_def)) = 0
     or position('notes_redacted' in lower(v_def)) = 0 then
    raise exception 'vetting states must carry mutually appropriate review evidence';
  end if;

  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid = 'public.worker_training'::regclass
    and conname = 'worker_training_completion_evidence_consistency';
  if v_def is null
     or position('status = ''passed''' in lower(v_def)) = 0
     or position('completed_at is not null' in lower(v_def)) = 0
     or position('verified_by is not null' in lower(v_def)) = 0
     or position('status <> ''passed''' in lower(v_def)) = 0
     or position('verified_by is null' in lower(v_def)) = 0 then
    raise exception 'training states must distinguish passed completion evidence';
  end if;
end $$;
