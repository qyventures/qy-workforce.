#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${QY_WORKFORCE_AGENT_LOG_DIR:-/var/log/qy-workforce-agent-farm}"
STATE_DIR="${QY_WORKFORCE_AGENT_STATE_DIR:-/var/lib/qy-workforce-agent-farm}"
LOCK_FILE="${QY_WORKFORCE_AGENT_LOCK:-/var/lock/qy-workforce-agent-farm.lock}"
mkdir -p "$LOG_DIR" "$STATE_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "agent farm already running; skipping overlapping cycle"
  exit 0
fi

cd "$ROOT"
git fetch origin main --quiet || true
MAIN_SHA="$(git rev-parse origin/main 2>/dev/null || git rev-parse HEAD)"

COUNTER_FILE="$STATE_DIR/cycle"
CYCLE=0
if [ -f "$COUNTER_FILE" ]; then
  CYCLE="$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)"
fi
CYCLE=$((CYCLE + 1))
printf '%s\n' "$CYCLE" > "$COUNTER_FILE"

run_agent() {
  local role="$1" branch="$2"
  echo "[$(date --iso-8601=seconds)] starting $role (cycle $CYCLE)" >"$LOG_DIR/$role.log"
  set +e
  "$ROOT/scripts/vps-agent-farm/run-agent.sh" "$role" "$branch" >>"$LOG_DIR/$role.log" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq 75 ]; then
    date --iso-8601=seconds > "$STATE_DIR/codex-usage-limited"
    echo "Codex usage limit reached; stopping this cycle to avoid waste." >>"$LOG_DIR/$role.log"
    return 75
  fi
  return "$rc"
}

# Cost-aware hourly orchestration for a hard credit budget:
# - backend is the critical path and runs every cycle
# - mobile runs every second cycle
# - web and ops alternate, so only one runs each cycle
# - QA runs every third cycle, and only after meaningful main changes
# - release runs every fourth cycle, and only after main changed since its last validation
# This keeps an hourly development rhythm without firing six context-heavy Codex sessions every hour.

if ! run_agent backend vps/backend; then
  rc=$?
  [ "$rc" -eq 75 ] && exit 0
fi

# Run at most two feature agents concurrently after backend.
pids=()
roles=()
if (( CYCLE % 2 == 0 )); then
  (run_agent mobile vps/mobile) & pids+=("$!"); roles+=("mobile")
fi
if (( CYCLE % 2 == 0 )); then
  (run_agent web vps/web) & pids+=("$!"); roles+=("web")
else
  (run_agent ops vps/ops) & pids+=("$!"); roles+=("ops")
fi
for pid in "${pids[@]}"; do wait "$pid" || true; done

QA_SHA_FILE="$STATE_DIR/qa-main-sha"
QA_LAST="$(cat "$QA_SHA_FILE" 2>/dev/null || true)"
if (( CYCLE % 3 == 0 )) && [ "$MAIN_SHA" != "$QA_LAST" ]; then
  if run_agent qa vps/qa; then printf '%s\n' "$MAIN_SHA" > "$QA_SHA_FILE"; fi
fi

RELEASE_SHA_FILE="$STATE_DIR/release-main-sha"
RELEASE_LAST="$(cat "$RELEASE_SHA_FILE" 2>/dev/null || true)"
if (( CYCLE % 4 == 0 )) && [ "$MAIN_SHA" != "$RELEASE_LAST" ]; then
  if run_agent release vps/release; then printf '%s\n' "$MAIN_SHA" > "$RELEASE_SHA_FILE"; fi
fi

{
  echo "QY Workforce cost-aware VPS farm cycle $CYCLE completed at $(date --iso-8601=seconds)"
  echo "main=$MAIN_SHA"
  echo "policy=backend hourly; mobile 2h; web/ops alternate hourly; QA 3h-on-change; release 4h-on-change"
  for role in backend mobile web ops qa release; do
    [ -f "$LOG_DIR/$role.log" ] || continue
    echo "--- $role ---"
    tail -n 6 "$LOG_DIR/$role.log" 2>/dev/null || true
  done
} > "$LOG_DIR/latest-summary.log"

date --iso-8601=seconds > "$LOG_DIR/last-success.txt"
