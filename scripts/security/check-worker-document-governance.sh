#!/usr/bin/env bash
set -euo pipefail
f="supabase/migrations/202609020335_worker_document_governance.sql"
test -f "$f"
grep -q "alter table public.worker_documents enable row level security" "$f"
grep -q "revoke insert, update, delete on public.worker_documents from anon, authenticated" "$f"
grep -q "storage_object_key !~\* '\^https?://'" "$f"
grep -q "public.is_ops()" "$f"
grep -q "worker_document.reviewed" "$f"
grep -q "retired document is immutable" "$f"
! grep -qiE 'public_url|service_role|raw_image|base64' "$f"
echo "worker document governance: PASS"
