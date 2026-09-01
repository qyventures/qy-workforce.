#!/usr/bin/env bash
set -euo pipefail

FILE="supabase/migrations/202609020438_worker_availability_leave_governance.sql"
test -f "$FILE"

grep -q "create table if not exists public.worker_availability_exceptions" "$FILE"
grep -q "enable row level security" "$FILE"
grep -q "revoke insert, update, delete on public.worker_availability_exceptions from anon, authenticated" "$FILE"
grep -q "workers read own availability exceptions" "$FILE"
grep -q "privileged read availability exceptions" "$FILE"
grep -q "create or replace function public.submit_worker_availability_exception" "$FILE"
grep -q "create or replace function public.review_worker_availability_exception" "$FILE"
grep -q "create or replace function public.cancel_own_worker_availability_exception" "$FILE"
grep -q "requester cannot review own exception" "$FILE"
grep -q "supporting document not owned by worker" "$FILE"
grep -q "worker_availability_exception.submitted" "$FILE"
grep -q "worker_availability_exception.reviewed" "$FILE"
grep -q "worker_availability_exception.cancelled" "$FILE"

if grep -Eqi 'raw_(medical|image|document)|public_url|https?://' "$FILE"; then
  echo "Unexpected raw/public document storage marker in availability governance migration" >&2
  exit 1
fi

echo "worker availability/leave governance: PASS"
