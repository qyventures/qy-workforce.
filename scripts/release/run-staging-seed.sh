#!/usr/bin/env bash
set -euo pipefail

# This seed is deliberately opt-in and only contains synthetic reference/demo
# records. It never creates auth users and never prints the connection string.
: "${STAGING_DATABASE_URL:?Set STAGING_DATABASE_URL to a staging-only Postgres connection URL}"
: "${STAGING_SEED_CONFIRMATION:?Set STAGING_SEED_CONFIRMATION=I_UNDERSTAND_SYNTHETIC_ONLY to run the staging seed}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

if [[ "$STAGING_SEED_CONFIRMATION" != 'I_UNDERSTAND_SYNTHETIC_ONLY' ]]; then
  echo 'Refusing to seed: set STAGING_SEED_CONFIRMATION=I_UNDERSTAND_SYNTHETIC_ONLY.' >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo 'psql is required to run the staging seed.' >&2
  exit 2
fi

psql "$STAGING_DATABASE_URL" --no-psqlrc --set ON_ERROR_STOP=1 --file "$repo_root/supabase/seed/staging.sql" >/dev/null
echo 'Synthetic staging seed applied.'
