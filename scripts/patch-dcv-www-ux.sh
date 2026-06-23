#!/bin/bash
# Idempotent DCV www UX patch (v5):
# - same-user-oldest-connection: prod-style — paste same URL in browser 2, login evicts browser 1.
# - lab-stale-tab-guard.js: evicted browser 1 cannot auto-reconnect and steal browser 2.
set -u

MARKER=/etc/lab/dcv-www-ux-v5.done
LOG_TAG="[dcv-ux-patch]"
V1_WRONG_MSG='You already have an active lab session in another browser tab or window. Please log out from that session first, then try again here.'
V1_WRONG_MSG_OLD='You already have an active session/connection running in the browser'

log() { echo "$LOG_TAG $*"; }

if [ -f "$MARKER" ]; then
  log "already applied v5 ($(cat "$MARKER" 2>/dev/null || echo ok))"
  POLICY_OK=0
  if [ -f /etc/dcv/dcv.conf ] && grep -q 'same-user-oldest-connection' /etc/dcv/dcv.conf 2>/dev/null; then
    POLICY_OK=1
  fi
  if [ "$POLICY_OK" -eq 1 ]; then
    exit 0
  fi
  log "marker present but eviction policy missing/wrong — re-applying policy"
fi

if [ -f /etc/dcv/dcv.conf ]; then
  if grep -q 'reject-new-connection' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i 's|client-eviction-policy = "reject-new-connection"|client-eviction-policy = "same-user-oldest-connection"|g' /etc/dcv/dcv.conf
    log "updated client-eviction-policy to same-user-oldest-connection"
  elif ! grep -q 'same-user-oldest-connection' /etc/dcv/dcv.conf 2>/dev/null; then
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

find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG}\.|The connection has been closed.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG}|The connection has been closed|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG_OLD}\.|The connection has been closed.|g" {} + 2>/dev/null || true
find /usr/share/dcv/www -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) \
  -exec sed -i "s|${V1_WRONG_MSG_OLD}|The connection has been closed|g" {} + 2>/dev/null || true

cat >/usr/share/dcv/www/custom-popup.js <<'DCVPOP'
if(!window.__lab_stop_hint_shown){window.__lab_stop_hint_shown=1;try{var n=parseInt(localStorage.getItem("lab_warn_count")||"0",10);if(n<3){localStorage.setItem("lab_warn_count",String(n+1));alert("Important: Closing this browser tab does NOT stop your lab session. It keeps running in the background. When you are done, click Stop Lab on the main portal.");}}catch(e){}}
DCVPOP
chmod 644 /usr/share/dcv/www/custom-popup.js || true

cat >/usr/share/dcv/www/lab-stale-tab-guard.js <<'LABGUARD'
(function(){var blocked=false,hadOpen=false;var O=window.WebSocket;function W(u,p){if(blocked){throw new Error("lab stale tab");}var s=new O(u,p);s.addEventListener("open",function(){hadOpen=true;});s.addEventListener("close",function(){if(hadOpen){blocked=true;}});return s;}W.prototype=O.prototype;W.CONNECTING=O.CONNECTING;W.OPEN=O.OPEN;W.CLOSING=O.CLOSING;W.CLOSED=O.CLOSED;window.WebSocket=W;})();
LABGUARD
chmod 644 /usr/share/dcv/www/lab-stale-tab-guard.js || true

if [ -f /usr/share/dcv/www/index.html ]; then
  if ! grep -q custom-popup.js /usr/share/dcv/www/index.html 2>/dev/null; then
    sed -i 's|</head>|<script src="custom-popup.js"></script></head>|' /usr/share/dcv/www/index.html 2>/dev/null || true
  fi
  if ! grep -q lab-stale-tab-guard.js /usr/share/dcv/www/index.html 2>/dev/null; then
    sed -i 's|</head>|<script src="lab-stale-tab-guard.js"></script></head>|' /usr/share/dcv/www/index.html 2>/dev/null || true
  fi
fi

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
rm -f /etc/lab/dcv-www-ux-v1.done /etc/lab/dcv-www-ux-v2.done /etc/lab/dcv-www-ux-v3.done /etc/lab/dcv-www-ux-v4.done 2>/dev/null || true
date -u +%Y-%m-%dT%H:%M:%SZ >"$MARKER"
log "done v5 marker=$MARKER"
exit 0
