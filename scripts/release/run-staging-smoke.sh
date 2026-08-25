#!/usr/bin/env bash
set -euo pipefail

# Safe HTTP smoke test for an already-deployed staging web build. It never
# prints environment values or request bodies.
: "${STAGING_WEB_URL:?Set STAGING_WEB_URL to the deployed staging web URL}"

base_url="${STAGING_WEB_URL%/}"
case "$base_url" in
  https://*) ;;
  *) echo 'STAGING_WEB_URL must use https.' >&2; exit 2 ;;
esac

headers_file="$(mktemp)"
trap 'rm -f "$headers_file"' EXIT

check_page() {
  local path="$1"
  local status
  status="$(curl --fail --silent --show-error --location --max-time 20 --output /dev/null --dump-header "$headers_file" --write-out '%{http_code}' "$base_url$path")"
  [[ "$status" == '200' ]] || { echo "Expected 200 for $path, got $status" >&2; exit 1; }
  grep -qi '^x-content-type-options: nosniff' "$headers_file" || { echo "Missing nosniff header for $path" >&2; exit 1; }
  grep -qi '^x-frame-options: DENY' "$headers_file" || { echo "Missing DENY frame header for $path" >&2; exit 1; }
}

check_page '/'
check_page '/privacy'
check_page '/terms'
check_page '/ops/login'
echo 'Staging web smoke test passed.'
