#!/bin/bash
# Idempotent DCV www UX patch (v3):
# - Webapp-like DCV login: same-user-oldest-connection + max-concurrent-clients 1 (backend).
#   A new browser login evicts the oldest connection for the same DCV owner.
# - Reverts v2 "reject 2nd browser" policy and duplicate-session message overrides.
# - Stop Lab tab-close reminder via custom-popup.js
#
# Reverts mistaken v1 sed that replaced "The connection has been closed" everywhere.
set -u

MARKER=/etc/lab/dcv-www-ux-v3.done
LOG_TAG="[dcv-ux-patch]"
V1_WRONG_MSG='You already have an active lab session in another browser tab or window. Please log out from that session first, then try again here.'
V1_WRONG_MSG_OLD='You already have an active session/connection running in the browser'
DUP_MSG='You already have an active lab session in another browser tab or window. Please log out from that session first, then try again here.'

log() { echo "$LOG_TAG $*"; }

if [ -f "$MARKER" ]; then
  log "already applied v3 ($(cat "$MARKER" 2>/dev/null || echo ok))"
  exit 0
fi

if [ -f /etc/dcv/dcv.conf ]; then
  if grep -q 'reject-new-connection' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i 's|client-eviction-policy = "reject-new-connection"|client-eviction-policy = "same-user-oldest-connection"|g' /etc/dcv/dcv.conf
    log "updated client-eviction-policy to same-user-oldest-connection"
  elif ! grep -q 'client-eviction-policy' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i '/^\[server\]/a client-eviction-policy = "same-user-oldest-connection"' /etc/dcv/dcv.conf 2>/dev/null || true
    log "inserted client-eviction-policy same-user-oldest-connection"
  elif grep -q 'same-user-oldest-connection' /etc/dcv/dcv.conf 2>/dev/null; then
    log "client-eviction-policy already same-user-oldest-connection"
  fi
fi

if [ ! -d /usr/share/dcv/www ]; then
  log "ERROR: /usr/share/dcv/www not found"
  exit 1
fi

# Revert v1 mistaken replacements.
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG}\.|The connection has been closed.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG}|The connection has been closed|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG_OLD}\.|The connection has been closed.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG_OLD}|The connection has been closed|g" {} + 2>/dev/null || true

# Revert v2 duplicate-session message override (v3 evicts oldest client instead of blocking).
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${DUP_MSG}\.|Maximum number of clients reached.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${DUP_MSG}|Maximum number of clients reached|g" {} + 2>/dev/null || true

cat >/usr/share/dcv/www/custom-popup.js <<'DCVPOP'
if(!window.__lab_stop_hint_shown){window.__lab_stop_hint_shown=1;try{var n=parseInt(localStorage.getItem("lab_warn_count")||"0",10);if(n<3){localStorage.setItem("lab_warn_count",String(n+1));alert("Important: Closing this browser tab does NOT stop your lab session. It keeps running in the background. When you are done, click Stop Lab on the main portal.");}}catch(e){}}
DCVPOP
chmod 644 /usr/share/dcv/www/custom-popup.js || true

if [ -f /usr/share/dcv/www/index.html ] && ! grep -q custom-popup.js /usr/share/dcv/www/index.html 2>/dev/null; then
  sed -i 's|</head>|<script src="custom-popup.js"></script></head>|' /usr/share/dcv/www/index.html 2>/dev/null || true
fi

# Restart dcvserver only when no virtual sessions (policy reload; avoid killing active desktops).
ACTIVE_SESSIONS=0
if command -v dcv >/dev/null 2>&1; then
  ACTIVE_SESSIONS=$(sudo dcv list-sessions 2>/dev/null | awk 'NR>1 && NF {c++} END {print c+0}')
fi
if [ "${ACTIVE_SESSIONS:-0}" -eq 0 ]; then
  systemctl restart dcvserver 2>/dev/null || true
  log "restarted dcvserver (no active sessions)"
else
  log "skipped dcvserver restart ($ACTIVE_SESSIONS active session(s)); policy applies on next session"
fi

install -d /etc/lab
rm -f /etc/lab/dcv-www-ux-v1.done 2>/dev/null || true
date -u +%Y-%m-%dT%H:%M:%SZ >"$MARKER"
log "done v3 marker=$MARKER"
exit 0
