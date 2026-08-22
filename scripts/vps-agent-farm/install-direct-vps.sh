#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/root/qy-workforce}"
SERVICE_USER="${SERVICE_USER:-root}"
RUN_INTERVAL_MINUTES="${RUN_INTERVAL_MINUTES:-60}"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Expected existing repo at $REPO_DIR" >&2
  exit 1
fi

cd "$REPO_DIR"
git fetch origin main
git checkout main
git pull --ff-only origin main
chmod +x scripts/vps-agent-farm/run-agent.sh scripts/vps-agent-farm/run-farm.sh

cat >/usr/local/bin/qy-workforce-agent-farm <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="${REPO_DIR:-/root/qy-workforce}"
cd "$REPO_DIR"
git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || true
git pull --ff-only origin main >/dev/null 2>&1 || true
export GITHUB_WORKSPACE="$REPO_DIR"
export RUNNER_TEMP="/tmp/qy-workforce-direct"
export QY_WORKFORCE_AGENT_LOG_DIR="/var/log/qy-workforce-agent-farm"
export QY_WORKFORCE_AGENT_STATE_DIR="/var/lib/qy-workforce-agent-farm"
mkdir -p "$RUNNER_TEMP" "$QY_WORKFORCE_AGENT_LOG_DIR" "$QY_WORKFORCE_AGENT_STATE_DIR"
exec "$REPO_DIR/scripts/vps-agent-farm/run-farm.sh"
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
Description=Run QY Workforce cost-aware VPS agent farm every ${RUN_INTERVAL_MINUTES} minutes

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
systemctl restart qy-workforce-agent-farm.timer

echo "Installed hourly cost-aware VPS agent farm."
echo "Policy: backend hourly; mobile every 2h; web/ops alternate hourly; QA every 3h on change; release every 4h on change."
echo "Logs: /var/log/qy-workforce-agent-farm"
systemctl --no-pager --full status qy-workforce-agent-farm.timer || true
