#!/usr/bin/env bash
set -euo pipefail

# Use a staging-only connection value supplied by the shell or CI secret store.
# The repository intentionally has no database URL fallback.
: "${STAGING_DATABASE_URL:?Set STAGING_DATABASE_URL to a staging-only Postgres connection URL}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

if ! command -v psql >/dev/null 2>&1; then
  echo 'psql is required to run Supabase SQL checks.' >&2
  exit 2
fi

# Every SQL file under supabase/tests is an executable regression check. Some
# newer checks intentionally use a domain name rather than the *_checks suffix.
for check in "$repo_root"/supabase/tests/*.sql; do
  echo "Running ${check}"
  psql "$STAGING_DATABASE_URL" --no-psqlrc --set ON_ERROR_STOP=1 --file "$check" >/dev/null
done

echo 'Supabase staging checks passed.'
