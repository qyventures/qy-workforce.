#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:?role required}"
BRANCH="${2:?branch required}"
BASE_DIR="${RUNNER_TEMP:-/tmp}/qy-workforce-agent-farm"
REPO_DIR="$BASE_DIR/repos/$ROLE"
SOURCE_REPO="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE required}"
REMOTE_URL="$(git -C "$SOURCE_REPO" remote get-url origin)"
mkdir -p "$BASE_DIR/repos"

case "$ROLE" in
  mobile)
    MODEL="gpt-5.6-terra"
    PROMPT='You are the QY Workforce mobile product agent. Work only on apps/mobile and directly related mobile config/tests/docs. V1 feature scope is now frozen except for launch blockers. Prioritize product polish and end-to-end pilot readiness: redesign worker home around greeting/status, nearby/recommended shifts, upcoming shift, weekly earnings and contextual clock-in; use bottom navigation Home | Jobs | My Shifts | Earnings | Profile; make shift cards scan-friendly with role, pay, date/time, distance/location, availability and one clear action; replace internal wording like deployment readiness with worker-friendly ready-to-work progress; preserve secure OTP, onboarding, consent, assignment, GPS attendance, timesheets, accessibility and offline/error states. Keep UI original and modern; do not copy YY Circle. Preserve server-side authorization/RLS and never use production credentials. Prefer coherent UX improvements over new backend features. Run focused tests/typechecks and keep iOS+Android preview-build ready. Do not checkout/rebase/push; the wrapper handles git.'
    ;;
  web)
    MODEL="gpt-5.6-terra"
    PROMPT='You are the QY Workforce public website product agent. Work only on public website portions under apps/web and directly related tests/docs. V1 feature scope is frozen except for launch blockers. Prioritize a polished recruitment/employer-conversion website: strong original QY Workforce visual system, responsive navigation, credible employer and worker journeys, clear CTAs, real-looking product UI sections, industry use cases, trust/compliance, privacy/terms, SEO, accessibility and privacy-safe analytics. Improve the current engineer-MVP feel with stronger hierarchy, typography, spacing, visual proof and conversion flow while avoiding copied YY Circle text/design. Ensure a worker recruitment / register-interest path can go live before Singpass production approval, with a compliant manual/non-Singpass fallback. Do not touch Ops/Admin unless shared layout requires it. Do not use production credentials or submit real leads. Prefer launch polish and deployability over new scope. Do not checkout/rebase/push.'
    ;;
  ops)
    MODEL="gpt-5.6-terra"
    PROMPT='You are the QY Workforce Ops/Admin product agent. Work only on Ops/Admin routes/components/tests under apps/web and directly related docs. V1 feature scope is frozen except for launch blockers. Prioritize making existing flows pilot-usable and clear: worker review, shift creation, supervisor approvals, attendance exceptions, timesheets, clients/sites, fulfilment and margin reporting. Improve information hierarchy, empty/loading/error/success states and operator efficiency without adding speculative features. Preserve route protection, least privilege, pseudonymisation and server-side audited RPC boundaries. Do not use production credentials. Run focused checks and keep staging deployable. Do not checkout/rebase/push.'
    ;;
  backend)
    MODEL="gpt-5.6-sol"
    PROMPT='You are the QY Workforce backend release-blocker agent. Work only on supabase migrations/tests and backend/security docs. V1 feature scope is frozen. Do not add new product features unless required to complete an existing end-to-end pilot flow or fix a security/compliance/reliability blocker. Prioritize integration correctness, RLS/RPC invariants, worker readiness/vetting/training, shift acceptance, attendance/geofence, timesheets/approvals/payroll, margin reporting, retention/privacy, and Singpass/Myinfo staging-provider readiness. Keep identity verification, residency and work eligibility separate. Maintain a manual/non-Singpass fallback as required. Never use production credentials. Prefer tests, fixes and idempotent migrations over scope expansion. Do not checkout/rebase/push.'
    ;;
  qa)
    MODEL="gpt-5.6-luna"
    PROMPT='You are the QY Workforce QA/security release-gate agent. Treat V1 scope as frozen. Validate complete worker and Ops journeys, CI reliability, RLS/authorization invariants, secret exposure, dependency/SBOM/SAST readiness, PDPA minimisation/retention, OWASP mobile/web/API risks, accessibility basics and regression tests. Focus on release-blocking defects and staging evidence. Fix only safe, clearly justified issues; do not expand scope. Never use production credentials. Do not checkout/rebase/push.'
    ;;
  release)
    MODEL="gpt-5.6-terra"
    PROMPT='You are the QY Workforce release/staging agent. V1 feature scope is frozen. Drive convergence to a testable staging release: staging env/config validation, migration order, seed/smoke-test tooling, end-to-end pilot checklist, Expo EAS Android/iOS preview configuration, web deployment readiness, signing prerequisites and release evidence. Prefer producing a usable website and installable preview builds over adding features. Never use or expose production secrets; do not publish to stores or contact users without explicit approval. Fix release blockers that can be solved in code and state exact external credentials/approvals needed when blocked. Do not checkout/rebase/push.'
    ;;
  *) echo "unknown role: $ROLE" >&2; exit 2 ;;
esac

# Use one independent local clone per role. This avoids shared-ref/worktree lock races
# when multiple VPS agents fetch/rebase concurrently.
if [ ! -d "$REPO_DIR/.git" ]; then
  rm -rf "$REPO_DIR"
  git clone --no-tags "$REMOTE_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
git remote set-url origin "$REMOTE_URL"
git fetch --no-tags origin main "$BRANCH" 2>/dev/null || git fetch --no-tags origin main

if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git checkout -B "$BRANCH" "origin/$BRANCH"
  git rebase origin/main || { git rebase --abort || true; git reset --hard origin/main; }
else
  git checkout -B "$BRANCH" origin/main
fi

git config user.name "QY Workforce VPS Agent"
git config user.email "qyventures@users.noreply.github.com"

CODEX=(codex exec)
HELP="$(codex exec --help 2>&1 || true)"
if grep -q -- '--model' <<<"$HELP"; then CODEX+=(--model "$MODEL"); fi
if grep -q -- '--full-auto' <<<"$HELP"; then CODEX+=(--full-auto); fi
if grep -q -- '--sandbox' <<<"$HELP"; then CODEX+=(--sandbox workspace-write); fi

echo "QY_WORKFORCE_CODEX_MODEL=$MODEL"
CODEX_LOG="$(mktemp)"
set +e
printf '%s\n' "$PROMPT" | timeout 35m "${CODEX[@]}" - 2>&1 | tee "$CODEX_LOG"
CODEX_RC=${PIPESTATUS[1]}
set -e

if grep -qi "hit your usage limit" "$CODEX_LOG"; then
  echo "CODEX_USAGE_LIMITED=1"
  rm -f "$CODEX_LOG"
  exit 75
fi
rm -f "$CODEX_LOG"

# A model/tool failure should not accidentally commit partial edits.
if [ "$CODEX_RC" -ne 0 ]; then
  echo "codex exited with status $CODEX_RC; leaving branch unchanged" >&2
  git reset --hard HEAD
  exit "$CODEX_RC"
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "vps($ROLE): autonomous pilot-readiness progress"
  git push origin "HEAD:$BRANCH"
fi
