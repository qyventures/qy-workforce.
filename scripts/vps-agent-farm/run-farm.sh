#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${QY_WORKFORCE_AGENT_LOG_DIR:-/var/log/qy-workforce-agents}"
LOCK_FILE="${QY_WORKFORCE_AGENT_LOCK:-/tmp/qy-workforce-agent-farm.lock}"
mkdir -p "$LOG_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "agent farm already running; skipping overlapping cycle"
  exit 0
fi

cd "$ROOT"
git fetch origin main --quiet || true

run_agent() {
  local role="$1" branch="$2"
  "$ROOT/scripts/vps-agent-farm/run-agent.sh" "$role" "$branch" >"$LOG_DIR/$role.log" 2>&1
}

# Keep at most three coding agents active concurrently on the 2 vCPU / 4 GB VPS.
run_agent mobile vps/mobile & p1=$!
run_agent web vps/web & p2=$!
run_agent ops vps/ops & p3=$!
wait "$p1" || true
wait "$p2" || true
wait "$p3" || true

run_agent backend vps/backend || true

# QA and release run after feature writers so expensive validation does not compete
# with three simultaneous Codex sessions.
run_agent qa vps/qa & p4=$!
run_agent release vps/release & p5=$!
wait "$p4" || true
wait "$p5" || true

{
  echo "QY Workforce VPS farm cycle completed at $(date --iso-8601=seconds)"
  for role in mobile web ops backend qa release; do
    echo "--- $role ---"
    tail -n 8 "$LOG_DIR/$role.log" 2>/dev/null || true
  done
} > "$LOG_DIR/latest-summary.log"
