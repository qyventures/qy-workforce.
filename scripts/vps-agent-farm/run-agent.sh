#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:?role required}"
BRANCH="${2:?branch required}"
BASE_DIR="${RUNNER_TEMP:-/tmp}/qy-workforce-agent-farm"
WORKTREE="$BASE_DIR/$ROLE"
mkdir -p "$BASE_DIR"

case "$ROLE" in
  mobile)
    PROMPT='You are the QY Workforce mobile agent. Work only on apps/mobile and directly related mobile config/tests/docs. Improve the React Native/Expo iOS+Android worker experience toward pilot readiness: auth/onboarding/readiness, shift discovery/acceptance, assignment detail, GPS attendance, timesheets/earnings, navigation, accessibility, offline/error states, staging build readiness. Preserve server-side authorization/RLS and do not use production credentials. Make several coherent improvements in this run when safe. Do not checkout/rebase/push; the wrapper handles git. Avoid expensive full builds; run only focused tests/typechecks needed for your changes.'
    ;;
  web)
    PROMPT='You are the QY Workforce public website agent. Work only on the public website portions under apps/web and directly related tests/docs. Push the original QY Workforce website to pilot readiness with employer and worker journeys, industries, how-it-works, trust/compliance, privacy/terms, SEO, responsive conversion UX and privacy-safe analytics. Do not copy YY Circle text/design. Do not touch Ops/Admin unless required for shared layout. Do not use production credentials or submit real leads. Make several coherent improvements per run when safe. Do not checkout/rebase/push.'
    ;;
  ops)
    PROMPT='You are the QY Workforce Ops/Admin web agent. Work only on Ops/Admin routes/components/tests under apps/web and directly related docs. Prioritize worker review, shift creation, supervisor approvals, attendance exceptions, timesheets, clients/sites, fulfilment and margin reporting. Preserve route protection, least privilege, pseudonymisation and server-side audited RPC boundaries. Do not use production credentials. Make several coherent improvements per run when safe. Do not checkout/rebase/push.'
    ;;
  backend)
    PROMPT='You are the QY Workforce backend agent. Work only on supabase migrations/tests and backend/security docs. Prioritize secure RLS/RPCs, worker readiness/vetting/training, shift matching/capacity, attendance/geofence, timesheets/approvals/payroll, margin reporting, retention/privacy controls and mock/staging Singpass abstraction. Keep identity, residency and work eligibility separate. Never use production credentials. Prefer idempotent migrations and add invariants/tests. Make several coherent improvements per run when safe. Do not checkout/rebase/push.'
    ;;
  qa)
    PROMPT='You are the QY Workforce QA/security agent. Review current main for release-blocking defects and security regressions. Focus on CI reliability, RLS/authorization invariants, secret exposure, dependency/SBOM/SAST readiness, PDPA data minimisation/retention, OWASP mobile/web/API issues and regression tests. Fix only safe, clearly justified issues; do not expand product scope. Do not use production credentials. Do not checkout/rebase/push.'
    ;;
  release)
    PROMPT='You are the QY Workforce release/staging agent. Focus on build/release readiness only: staging config examples, migration ordering, seed/smoke-test tooling, Expo EAS Android/iOS preview configuration, web build/deploy readiness and release checklists. Never use or expose production secrets and never publish to stores or contact users. Fix release blockers that can be solved in code. Do not checkout/rebase/push.'
    ;;
  *) echo "unknown role: $ROLE" >&2; exit 2 ;;
esac

cd "$GITHUB_WORKSPACE"
git fetch origin main "$BRANCH" 2>/dev/null || git fetch origin main
rm -rf "$WORKTREE"
if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git worktree add -B "$BRANCH" "$WORKTREE" "origin/$BRANCH"
  cd "$WORKTREE"
  git rebase origin/main || { git rebase --abort || true; git reset --hard origin/main; }
else
  git worktree add -b "$BRANCH" "$WORKTREE" origin/main
  cd "$WORKTREE"
fi

git config user.name "QY Workforce VPS Agent"
git config user.email "qyventures@users.noreply.github.com"

CODEX=(codex exec)
HELP="$(codex exec --help 2>&1 || true)"
if grep -q -- '--full-auto' <<<"$HELP"; then CODEX+=(--full-auto); fi
if grep -q -- '--sandbox' <<<"$HELP"; then CODEX+=(--sandbox workspace-write); fi

printf '%s\n' "$PROMPT" | timeout 35m "${CODEX[@]}" - || true

git add -A
if ! git diff --cached --quiet; then
  git commit -m "vps($ROLE): autonomous pilot-readiness progress"
  git push origin "HEAD:$BRANCH"
fi

git worktree remove "$WORKTREE" --force || true
