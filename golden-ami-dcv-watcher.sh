#!/usr/bin/env bash
# Run once on a clean lab template instance (as root), then create AMI from this instance.
# Backend will SSH-write /opt/semiconlabs/session-watch.json and restart semiconlabs-dcv-watch.service.

set -euo pipefail

if [[ "${EUID:-0}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { yum install -y python3 || dnf install -y python3 || true; }
command -v curl >/dev/null 2>&1 || { yum install -y curl || dnf install -y curl || true; }

mkdir -p /opt/semiconlabs

cat >/opt/semiconlabs/watch-dcv-logout.sh <<'WATCHER'
#!/usr/bin/env bash
set -euo pipefail

CFG=/opt/semiconlabs/session-watch.json
LOCK=/var/run/semiconlabs-dcv-watch.lock
POLL_SECONDS="${LAB_DCV_WATCH_POLL_SECONDS:-5}"

mkdir -p /var/run /var/log
exec 9>"$LOCK"
flock -n 9 || exit 0

while true; do
  if [ ! -s "$CFG" ]; then
    sleep "$POLL_SECONDS"
    continue
  fi

  SESSION_NAME="$(python3 -c 'import json;import sys;print(json.load(open(sys.argv[1])).get("dcv_session_name",""))' "$CFG" 2>/dev/null || true)"
  APP_SESSION_ID="$(python3 -c 'import json;import sys;print(json.load(open(sys.argv[1])).get("app_session_id",""))' "$CFG" 2>/dev/null || true)"
  CALLBACK_URL="$(python3 -c 'import json;import sys;print(json.load(open(sys.argv[1])).get("callback_url",""))' "$CFG" 2>/dev/null || true)"
  CALLBACK_SECRET="$(python3 -c 'import json;import sys;print(json.load(open(sys.argv[1])).get("callback_secret",""))' "$CFG" 2>/dev/null || true)"

  if [ -z "$SESSION_NAME" ] || [ -z "$APP_SESSION_ID" ] || [ -z "$CALLBACK_URL" ] || [ -z "$CALLBACK_SECRET" ]; then
    sleep "$POLL_SECONDS"
    continue
  fi

  if sudo dcv list-sessions --json 2>/dev/null | grep -Fq "\"$SESSION_NAME\""; then
    sleep "$POLL_SECONDS"
    continue
  fi
  if sudo dcv list-sessions 2>/dev/null | grep -Fq "$SESSION_NAME"; then
    sleep "$POLL_SECONDS"
    continue
  fi

  curl -sS -X POST "$CALLBACK_URL" \
    -H "Content-Type: application/json" \
    -H "X-Lab-Callback-Secret: $CALLBACK_SECRET" \
    --data "{\"session_id\":$APP_SESSION_ID}" >/dev/null || true

  rm -f "$CFG"
  sleep "$POLL_SECONDS"
done
WATCHER

chmod 700 /opt/semiconlabs/watch-dcv-logout.sh

cat >/etc/systemd/system/semiconlabs-dcv-watch.service <<'UNIT'
[Unit]
Description=Semiconlabs DCV logout watcher
After=network-online.target dcvserver.service
Wants=network-online.target

[Service]
Type=simple
Environment=LAB_DCV_WATCH_POLL_SECONDS=5
ExecStart=/opt/semiconlabs/watch-dcv-logout.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable semiconlabs-dcv-watch.service
systemctl restart semiconlabs-dcv-watch.service || true

echo "semiconlabs-dcv-watch installed. Create AMI from this instance, then set terraform ami_id / DEFAULT_LAB_CONFIGS.ami_id to the new id (repo default reference: ami-066401294ec783ea4)."
