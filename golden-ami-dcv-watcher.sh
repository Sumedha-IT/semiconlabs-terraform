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

  # P2: classify from last dcv.log lines and POST reason + truncated detail.
  python3 - "$CFG" <<'PY' || true
import glob, json, os, re, sys, urllib.request

cfg_path = sys.argv[1]
with open(cfg_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

session_id = cfg.get("app_session_id")
callback_url = (cfg.get("callback_url") or "").strip()
secret = (cfg.get("callback_secret") or "").strip()
if session_id is None or not callback_url or not secret:
    raise SystemExit(0)

chunks = []
for path in sorted(glob.glob("/var/log/dcv/*.log")):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            lines = fh.readlines()[-40:]
            if lines:
                chunks.append("# " + os.path.basename(path))
                chunks.extend(line.rstrip("\n") for line in lines)
    except Exception:
        pass
detail = "\n".join(chunks)[-3500:]
text = detail.lower()

def classify(t: str) -> str:
    if re.search(r"auth(entication)?\s*(fail|error|expired)|unauthorized|invalid\s*(token|cookie)|jwt|sso.*fail|verifier", t):
        return "auth_expired"
    if re.search(r"max(imum)?\s*(number\s*of\s*)?(concurrent\s*)?clients?|connection\s*limit|too many clients|client.*kicked|evict", t):
        return "max_clients"
    if re.search(r"premature|session\s+not\s+ready|before\s+.*ready|no\s+such\s+session", t):
        return "sso_premature"
    if re.search(r"idle\s*(timeout|disconnect)|gateway\s*timeout|proxy.*timeout|alb.*timeout|\b504\b|\b408\b", t):
        return "proxy_timeout"
    if re.search(r"network|connection\s*(reset|refused|closed|aborted)|broken\s*pipe|websocket.*(error|close|fail)|econnreset|etimedout", t):
        return "network_drop"
    if re.search(r"close[- ]session|session\s+(was\s+)?closed|server\s+closed|dcv\s+close|reboot|shutdown", t):
        return "server_closed_session"
    if re.search(r"logout|client\s*disconnect|user\s*closed|browser\s*closed", t):
        return "client_closed"
    return "client_closed" if not t.strip() else "unknown"

payload = {
    "session_id": int(session_id) if str(session_id).isdigit() else session_id,
    "reason": classify(text),
    "detail": detail or None,
}
req = urllib.request.Request(
    callback_url,
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Content-Type": "application/json",
        "X-Lab-Callback-Secret": secret,
    },
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        resp.read()
except Exception:
    pass
PY

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
systemctl enable --now semiconlabs-dcv-watch.service
echo "Installed semiconlabs-dcv-watch.service (reason+log snippet callback)"
