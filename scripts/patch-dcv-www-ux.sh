#!/bin/bash
# Idempotent DCV www UX patch - guard rev v9 (see Semiconlabs-backend lab-dcv-guard.script.ts)
set -u

MARKER=/etc/lab/dcv-www-ux-v6.done
GUARD_REV=v9
LOG_TAG="[dcv-ux-patch]"
V1_WRONG_MSG='You already have an active lab session in another browser tab or window. Please log out from that session first, then try again here.'
V1_WRONG_MSG_OLD='You already have an active session/connection running in the browser'

log() { echo "$LOG_TAG $*"; }

policy_in_session_mgmt() {
  awk '/^\[session-management\]/{f=1;next} /^\[/{f=0} f&&/max-concurrent-clients/{ok=1} END{exit !ok}' \
    /etc/dcv/dcv.conf 2>/dev/null
}
if [ -f /etc/lab/dcv-guard-rev ] && [ "$(cat /etc/lab/dcv-guard-rev 2>/dev/null)" = "$GUARD_REV" ]; then
  if [ -f "$MARKER" ] && policy_in_session_mgmt; then
    log "already applied guard=$GUARD_REV"
    exit 0
  fi
  log "guard rev ok but [session-management] policy missing - re-applying"
fi

if [ -f /etc/lab/dcv.conf.from-userdata ]; then
  log "skip dcv.conf (owned by user-data)"
elif [ -f /etc/dcv/dcv.conf ]; then
  # max-concurrent-clients belongs in [session-management]; client-eviction-policy belongs in
  # [session-management/automatic-console-session]. DCV ignores both in [connectivity] or [server]
  # and defaults to reject-new-connection (closes the NEW browser). Multi-browser takeover is
  # primarily enforced by the backend SSM eviction on page load; these settings are belt-and-
  # suspenders for console sessions and align dcv.conf with user-data bootstrap.
  before=$(md5sum /etc/dcv/dcv.conf 2>/dev/null | awk '{print $1}')
  sed -i '/client-eviction-policy/d;/max-concurrent-clients/d' /etc/dcv/dcv.conf
  if grep -q '^\[session-management\]' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i '/^\[session-management\]/a max-concurrent-clients = 1' /etc/dcv/dcv.conf
  fi
  if grep -q '^\[session-management/automatic-console-session\]' /etc/dcv/dcv.conf 2>/dev/null; then
    sed -i '/^\[session-management\/automatic-console-session\]/a client-eviction-policy = "same-user-oldest-connection"\nmax-concurrent-clients = 1' /etc/dcv/dcv.conf
  else
    printf '\n[session-management/automatic-console-session]\nclient-eviction-policy = "same-user-oldest-connection"\nmax-concurrent-clients = 1\n' >>/etc/dcv/dcv.conf
  fi
  after=$(md5sum /etc/dcv/dcv.conf 2>/dev/null | awk '{print $1}')
  if [ "$before" != "$after" ]; then
    log "set session-management eviction policy; restarting dcvserver"
    systemctl restart dcvserver 2>/dev/null || true
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
(function(){var REV='v9',blocked=false,tabId=Math.random().toString(36).slice(2),tabTs=Date.now();var LK='lab_dcv_tab_leader',activeWs=null;function demote(){if(blocked)return;blocked=true;try{sessionStorage.setItem('lab_dcv_blocked','1');}catch(e){}if(activeWs){try{activeWs.close();}catch(x){}activeWs=null;}}try{if(sessionStorage.getItem('lab_dcv_blocked')==='1')blocked=true;}catch(e){}function claim(){try{localStorage.setItem(LK,JSON.stringify({id:tabId,ts:tabTs,rev:REV}));}catch(e){}}try{claim();window.addEventListener('storage',function(e){if(e.key!==LK||!e.newValue)return;try{var n=JSON.parse(e.newValue);if(n.id!==tabId&&n.ts>tabTs)demote();}catch(x){}});setInterval(function(){try{var L=JSON.parse(localStorage.getItem(LK)||'{}');if(L.id&&L.id!==tabId&&L.ts>tabTs)demote();}catch(x){}},2000);}catch(e){}var O=window.WebSocket;function W(u,p){if(blocked)throw new Error('lab stale tab');var s=new O(u,p);activeWs=s;s.addEventListener('open',function(){claim();});return s;}W.prototype=O.prototype;W.CONNECTING=O.CONNECTING;W.OPEN=O.OPEN;W.CLOSING=O.CLOSING;W.CLOSED=O.CLOSED;window.WebSocket=W;function hideReconnect(){if(!blocked)return;document.querySelectorAll('button,a,[role=button]').forEach(function(el){var t=(el.textContent||'').toLowerCase();if(t.indexOf('reconnect')>=0||t.indexOf('connect again')>=0){el.style.pointerEvents='none';el.style.opacity='0.35';}});}var mo=new MutationObserver(hideReconnect);function startObs(){if(document.body)mo.observe(document.body,{childList:true,subtree:true});hideReconnect();}if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',startObs);else startObs();})();
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

install -d /etc/lab
echo "$GUARD_REV" >/etc/lab/dcv-guard-rev
rm -f /etc/lab/dcv-www-ux-v1.done /etc/lab/dcv-www-ux-v2.done /etc/lab/dcv-www-ux-v3.done /etc/lab/dcv-www-ux-v4.done /etc/lab/dcv-www-ux-v5.done 2>/dev/null || true
date -u +%Y-%m-%dT%H:%M:%SZ >"$MARKER"
log "done guard=$GUARD_REV"
exit 0
