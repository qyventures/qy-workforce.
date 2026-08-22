#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "install-systemd.sh must run as root" >&2
  exit 1
fi

REPO_DIR="${QY_WORKFORCE_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SERVICE=/etc/systemd/system/qy-workforce-agent-farm.service
TIMER=/etc/systemd/system/qy-workforce-agent-farm.timer

cat > "$SERVICE" <<EOF
[Unit]
Description=QY Workforce autonomous VPS agent farm
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$REPO_DIR
Environment=HOME=/root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/bash $REPO_DIR/scripts/vps-agent-farm/run-farm.sh
Nice=5
CPUWeight=60
MemoryHigh=3200M
TimeoutStartSec=3300

[Install]
WantedBy=multi-user.target
EOF

cat > "$TIMER" <<'EOF'
[Unit]
Description=Run QY Workforce VPS agent farm every 30 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=30min
AccuracySec=2min
Persistent=true
Unit=qy-workforce-agent-farm.service

[Install]
WantedBy=timers.target
EOF

chmod +x "$REPO_DIR/scripts/vps-agent-farm/run-agent.sh" "$REPO_DIR/scripts/vps-agent-farm/run-farm.sh"
mkdir -p /var/log/qy-workforce-agents
systemctl daemon-reload
systemctl enable --now qy-workforce-agent-farm.timer
systemctl start qy-workforce-agent-farm.service

systemctl --no-pager status qy-workforce-agent-farm.timer || true
systemctl --no-pager status qy-workforce-agent-farm.service || true
