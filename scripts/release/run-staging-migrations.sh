#!/usr/bin/env bash
set -euo pipefail

# Apply checked-in migrations through Supabase's migration ledger. This is
# intentionally explicit about the target so a local or production project
# cannot be selected by accident.
: "${STAGING_DATABASE_URL:?Set STAGING_DATABASE_URL to a staging-only Postgres connection URL}"
: "${STAGING_MIGRATION_CONFIRMATION:?Set STAGING_MIGRATION_CONFIRMATION=I_UNDERSTAND_STAGING_ONLY to apply migrations}"

if [[ "$STAGING_MIGRATION_CONFIRMATION" != 'I_UNDERSTAND_STAGING_ONLY' ]]; then
  echo 'Refusing to migrate: set STAGING_MIGRATION_CONFIRMATION=I_UNDERSTAND_STAGING_ONLY.' >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

node "$repo_root/scripts/release/verify-release-readiness.mjs"

if ! command -v supabase >/dev/null 2>&1; then
  echo 'Supabase CLI is required to apply staging migrations.' >&2
  exit 2
fi

supabase db push --db-url "$STAGING_DATABASE_URL" --workdir "$repo_root" --yes
echo 'Staging migrations applied through the Supabase migration ledger.'
