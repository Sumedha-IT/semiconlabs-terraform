#!/bin/bash
# Idempotent DCV www UX patch (v2):
# - Reject 2nd browser login (reject-new-connection + max-concurrent-clients 1 on sessions).
# - Customize ONLY "Maximum number of clients reached" (2nd login), NOT generic disconnect.
# - Stop Lab tab-close reminder via custom-popup.js
#
# Reverts mistaken v1 sed that replaced "The connection has been closed" everywhere.
set -u

MARKER=/etc/lab/dcv-www-ux-v2.done
LOG_TAG="[dcv-ux-patch]"
V1_WRONG_MSG='You already have an active lab session in another browser tab or window. Please log out from that session first, then try again here.'
V1_WRONG_MSG_OLD='You already have an active session/connection running in the browser'
DUP_MSG='You already have an active lab session in another browser tab or window. Please log out from that session first, then try again here.'

log() { echo "$LOG_TAG $*"; }

if [ -f "$MARKER" ]; then
  log "already applied v2 ($(cat "$MARKER" 2>/dev/null || echo ok))"
  exit 0
fi

if [ -f /etc/dcv/dcv.conf ]; then
  if grep -q 'same-user-oldest-connection' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i 's|client-eviction-policy = "same-user-oldest-connection"|client-eviction-policy = "reject-new-connection"|g' /etc/dcv/dcv.conf
    log "updated client-eviction-policy to reject-new-connection"
  elif ! grep -q 'client-eviction-policy' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i '/^\[server\]/a client-eviction-policy = "reject-new-connection"' /etc/dcv/dcv.conf 2>/dev/null || true
    log "inserted client-eviction-policy reject-new-connection"
  fi
fi

if [ ! -d /usr/share/dcv/www ]; then
  log "ERROR: /usr/share/dcv/www not found"
  exit 1
fi

find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG}\.|The connection has been closed.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG}|The connection has been closed|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG_OLD}\.|The connection has been closed.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG_OLD}|The connection has been closed|g" {} + 2>/dev/null || true

find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|Maximum number of clients reached\.|${DUP_MSG}|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|Maximum number of clients reached|${DUP_MSG}|g" {} + 2>/dev/null || true

cat >/usr/share/dcv/www/custom-popup.js <<'DCVPOP'
if(!window.__lab_stop_hint_shown){window.__lab_stop_hint_shown=1;try{var n=parseInt(localStorage.getItem("lab_warn_count")||"0",10);if(n<3){localStorage.setItem("lab_warn_count",String(n+1));alert("Important: Closing this browser tab does NOT stop your lab session. It keeps running in the background. When you are done, click Stop Lab on the main portal.");}}catch(e){}}
DCVPOP
chmod 644 /usr/share/dcv/www/custom-popup.js || true

if [ -f /usr/share/dcv/www/index.html ] && ! grep -q custom-popup.js /usr/share/dcv/www/index.html 2>/dev/null; then
  sed -i 's|</head>|<script src="custom-popup.js"></script></head>|' /usr/share/dcv/www/index.html 2>/dev/null || true
fi

# Do not restart dcvserver — kills active virtual sessions on running labs.
install -d /etc/lab
rm -f /etc/lab/dcv-www-ux-v1.done 2>/dev/null || true
date -u +%Y-%m-%dT%H:%M:%SZ >"$MARKER"
log "done v2 marker=$MARKER"
exit 0
