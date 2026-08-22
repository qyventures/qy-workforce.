#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/root/qy-workforce}"
SERVICE_USER="${SERVICE_USER:-root}"
RUN_INTERVAL_MINUTES="${RUN_INTERVAL_MINUTES:-120}"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Expected existing repo at $REPO_DIR" >&2
  exit 1
fi

cd "$REPO_DIR"
git fetch origin main
git checkout main
git pull --ff-only origin main
chmod +x scripts/vps-agent-farm/run-agent.sh

cat >/usr/local/bin/qy-workforce-agent-farm <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="${REPO_DIR:-/root/qy-workforce}"
LOG_DIR="/var/log/qy-workforce-agent-farm"
LOCK_FILE="/var/lock/qy-workforce-agent-farm.lock"
mkdir -p "$LOG_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "agent farm already running; skipping"
  exit 0
fi
cd "$REPO_DIR"
git fetch origin main
git checkout main
git pull --ff-only origin main
export GITHUB_WORKSPACE="$REPO_DIR"
export RUNNER_TEMP="/tmp/qy-workforce-direct"
mkdir -p "$RUNNER_TEMP"

roles=(mobile web ops backend)
branches=(vps/mobile vps/web vps/ops vps/backend)
pids=()
for i in "${!roles[@]}"; do
  role="${roles[$i]}"
  branch="${branches[$i]}"
  scripts/vps-agent-farm/run-agent.sh "$role" "$branch" >"$LOG_DIR/$role.log" 2>&1 &
  pids+=("$!")
  if (( ${#pids[@]} >= 3 )); then
    wait "${pids[0]}" || true
    pids=("${pids[@]:1}")
  fi
done
for pid in "${pids[@]}"; do wait "$pid" || true; done

scripts/vps-agent-farm/run-agent.sh qa vps/qa >"$LOG_DIR/qa.log" 2>&1 &
qa_pid=$!
scripts/vps-agent-farm/run-agent.sh release vps/release >"$LOG_DIR/release.log" 2>&1 &
release_pid=$!
wait "$qa_pid" || true
wait "$release_pid" || true

date --iso-8601=seconds > "$LOG_DIR/last-success.txt"
EOF
chmod +x /usr/local/bin/qy-workforce-agent-farm

cat >/etc/systemd/system/qy-workforce-agent-farm.service <<EOF
[Unit]
Description=QY Workforce direct VPS agent farm
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SERVICE_USER
WorkingDirectory=$REPO_DIR
Environment=REPO_DIR=$REPO_DIR
ExecStart=/usr/local/bin/qy-workforce-agent-farm
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat >/etc/systemd/system/qy-workforce-agent-farm.timer <<EOF
[Unit]
Description=Run QY Workforce VPS agent farm every ${RUN_INTERVAL_MINUTES} minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=${RUN_INTERVAL_MINUTES}min
Persistent=true
Unit=qy-workforce-agent-farm.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now qy-workforce-agent-farm.timer
systemctl start qy-workforce-agent-farm.service

sleep 2
systemctl --no-pager --full status qy-workforce-agent-farm.timer || true
systemctl --no-pager --full status qy-workforce-agent-farm.service || true

echo "Installed direct VPS agent farm. Logs: /var/log/qy-workforce-agent-farm"
