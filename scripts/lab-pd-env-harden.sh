#!/bin/bash
# PD/AL/DV DCV env harden: seed /data/tools/*source only (no /PD|/DV|/AL shortcuts),
# bash→tcsh handoff + XFCE Terminal login tcsh. No /efs, softlinks, or tool-tree chmod.
set -uo pipefail
LOG=/var/log/lab-bootstrap.log
lab_pd_log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [lab-pd-env] $*" | tee -a "$LOG"
}
# AD/SSSD users have no matching group name (group is e.g. "domain users").
# chown user:user fails; resolve the real primary group, fall back to just the user.
lab_pd_chown() {
  local user="$1"; shift
  local grp
  grp=$(id -gn "$user" 2>/dev/null || true)
  if [ -n "$grp" ]; then
    chown -R "$user:$grp" "$@" 2>/dev/null && return 0
  fi
  chown -R "$user" "$@" 2>/dev/null || true
}
# XFCE Terminal CustomCommand does not reliably split args; a bare "/bin/tcsh -l"
# is exec'd as one path -> "Failed to execute child process". Use a no-arg wrapper.
LAB_LOGIN_SHELL=/usr/local/bin/lab-login-shell
lab_pd_install_login_shell() {
  cat >"$LAB_LOGIN_SHELL" <<'EOF'
#!/bin/bash
# Launch a login tcsh so PD/AL/DV env (pdsource via /etc/profile.d) loads.
exec "$(command -v tcsh 2>/dev/null || echo /bin/tcsh)" -l
EOF
  chmod 755 "$LAB_LOGIN_SHELL"
}

# Rebuild source list for domain(s) in TOOLS_LIST — /data/tools only (FSx at /data).
lab_pd_rebuild_filtered_lst() {
  local raw=/etc/lab/efs-tool-sources.raw.lst
  local out=/etc/lab/efs-tool-sources.lst
  local f c _codes _keep
  install -d -m 0755 /etc/lab
  # World-readable mount config (no secrets); learners must be able to cat/source it.
  chmod 0755 /etc/lab/efs-mount.env 2>/dev/null || true
  TOOLS_LIST=""
  [ -r /etc/lab/efs-mount.env ] && . /etc/lab/efs-mount.env || true
  _codes="$TOOLS_LIST"
  if [ -z "$(echo "$_codes" | tr -d '[:space:]')" ]; then
    for c in PD DV AL; do
      [ -d "/data/tools/$c" ] && _codes="$_codes $c"
    done
  fi
  : >"$raw"
  for c in $_codes; do
    case "$c" in
      PD)
        for f in /data/tools/PD/pdsource /data/tools/pdsource; do
          [ -f "$f" ] && { echo "$f" >>"$raw"; break; }
        done
        ;;
      AL)
        for f in /data/tools/AL/alsource /data/tools/alsource; do
          [ -f "$f" ] && { echo "$f" >>"$raw"; break; }
        done
        ;;
      DV)
        for f in /data/tools/DV/dvsource /data/tools/dvsource; do
          [ -f "$f" ] && { echo "$f" >>"$raw"; break; }
        done
        ;;
      FUTURENSE|futurense)
        for f in /data/tools/PD/pdsource /data/tools/pdsource; do
          [ -f "$f" ] && { echo "$f" >>"$raw"; break; }
        done
        for f in /data/tools/DV/dvsource /data/tools/dvsource; do
          [ -f "$f" ] && { echo "$f" >>"$raw"; break; }
        done
        ;;
      esac
  done
  [ -s "$raw" ] || return 0
  : >"$out"
  while IFS= read -r f || [ -n "$f" ]; do
    case "$f" in ''|'#'*) continue ;; esac
    case "$f" in *yam4tp*) continue ;; esac
    case "$f" in */filtered-sources/) continue ;; esac
    if [ -n "$(echo "$_codes" | tr -d '[:space:]')" ]; then
      _keep=0
      case "$f" in
        *pdsource*|*PD/*|*PD) case " $_codes " in *" PD "*|*" FUTURENSE "*) _keep=1 ;; esac ;;
        *alsource*|*AL/*|*AL) case " $_codes " in *" AL "*) _keep=1 ;; esac ;;
        *dvsource*|*cdnsource*|*DV/*|*DV) case " $_codes " in *" DV "*|*" FUTURENSE "*) _keep=1 ;; esac ;;
        *) _keep=1 ;;
      esac
      [ "$_keep" = 1 ] || continue
    fi
    grep -qxF "$f" "$out" 2>/dev/null || printf '%s\n' "$f" >>"$out"
    lab_pd_log "source -> $f"
  done <"$raw"
}

lab_pd_patch_one_home() {
  local user="$1" home bashrc tcshrc cshrc
  [ -n "$user" ] || return 0
  home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6)
  [ -n "$home" ] && [ -d "$home" ] || return 0
  bashrc="$home/.bashrc"
  tcshrc="$home/.tcshrc"
  cshrc="$home/.cshrc"
  touch "$bashrc" 2>/dev/null || true
  if [ -f "$bashrc" ]; then
    sed -i '/zz-lab-efs-tools\.csh/d;/zz-futurense-lab-setup\.csh/d' "$bashrc" 2>/dev/null || true
  fi
  if [ -f "$bashrc" ] && ! grep -qF 'semiconlabs-lab-efs-tool-env' "$bashrc" 2>/dev/null; then
    {
      echo ''
      echo '# semiconlabs-lab-efs-tool-env'
      echo 'if [ -r /etc/profile.d/zz-lab-efs-tools.sh ]; then . /etc/profile.d/zz-lab-efs-tools.sh; fi'
    } >>"$bashrc"
    lab_pd_chown "$user" "$bashrc"
  fi
  for rc in "$tcshrc" "$cshrc"; do
    touch "$rc" 2>/dev/null || true
    if [ -f "$rc" ] && ! grep -qF 'semiconlabs-lab-efs-tool-env' "$rc" 2>/dev/null; then
      {
        echo '# semiconlabs-lab-efs-tool-env'
        echo 'if ( -r /etc/profile.d/zz-lab-efs-tools.csh ) source /etc/profile.d/zz-lab-efs-tools.csh'
      } >>"$rc"
      lab_pd_chown "$user" "$rc"
    fi
    if [ -f "$rc" ] && ! grep -qF 'semiconlabs-futurense-lab-setup' "$rc" 2>/dev/null; then
      {
        echo '# semiconlabs-futurense-lab-setup'
        echo 'if ( -r /etc/profile.d/zz-futurense-lab-setup.csh ) source /etc/profile.d/zz-futurense-lab-setup.csh'
      } >>"$rc"
      lab_pd_chown "$user" "$rc"
    fi
  done
  install -d "$home/.config/xfce4/terminal" 2>/dev/null || true
  cat >"$home/.config/xfce4/terminal/terminalrc" <<'EOF'
[Configuration]
CommandLoginShell=TRUE
RunCustomCommand=TRUE
CustomCommand=/usr/local/bin/lab-login-shell
EOF
  lab_pd_chown "$user" "$home/.config/xfce4"
  lab_pd_log "patched home for $user"
}

lab_pd_patch_home_rcs() {
  local home user bashrc tcshrc cshrc
  for home in /home/*; do
    [ -d "$home" ] || continue
    user=$(basename "$home")
    case "$user" in
      centos|cloud-user|ssm-user|ec2-user|ubuntu|admin) continue ;;
    esac
    bashrc="$home/.bashrc"
    tcshrc="$home/.tcshrc"
    cshrc="$home/.cshrc"
    touch "$bashrc" 2>/dev/null || true
    if [ -f "$bashrc" ]; then
      sed -i '/zz-lab-efs-tools\.csh/d;/zz-futurense-lab-setup\.csh/d' "$bashrc" 2>/dev/null || true
    fi
    if [ -f "$bashrc" ] && ! grep -qF 'semiconlabs-lab-efs-tool-env' "$bashrc" 2>/dev/null; then
      {
        echo ''
        echo '# semiconlabs-lab-efs-tool-env'
        echo 'if [ -r /etc/profile.d/zz-lab-efs-tools.sh ]; then . /etc/profile.d/zz-lab-efs-tools.sh; fi'
      } >>"$bashrc"
      lab_pd_chown "$user" "$bashrc"
    fi
    for rc in "$tcshrc" "$cshrc"; do
      touch "$rc" 2>/dev/null || true
      if [ -f "$rc" ] && ! grep -qF 'semiconlabs-lab-efs-tool-env' "$rc" 2>/dev/null; then
        {
          echo '# semiconlabs-lab-efs-tool-env'
          echo 'if ( -r /etc/profile.d/zz-lab-efs-tools.csh ) source /etc/profile.d/zz-lab-efs-tools.csh'
        } >>"$rc"
        lab_pd_chown "$user" "$rc"
      fi
      if [ -f "$rc" ] && ! grep -qF 'semiconlabs-futurense-lab-setup' "$rc" 2>/dev/null; then
        {
          echo '# semiconlabs-futurense-lab-setup'
          echo 'if ( -r /etc/profile.d/zz-futurense-lab-setup.csh ) source /etc/profile.d/zz-futurense-lab-setup.csh'
        } >>"$rc"
        lab_pd_chown "$user" "$rc"
      fi
    done
    install -d "$home/.config/xfce4/terminal" 2>/dev/null || true
    cat >"$home/.config/xfce4/terminal/terminalrc" <<'EOF'
[Configuration]
CommandLoginShell=TRUE
RunCustomCommand=TRUE
CustomCommand=/usr/local/bin/lab-login-shell
EOF
    lab_pd_chown "$user" "$home/.config/xfce4"
  done
}

lab_pd_install_profile_hooks() {
  cat >/etc/profile.d/zz-lab-efs-tools.sh <<'ZZLABEFS'
lab_efs_tools_profile_sh() {
  command -v tcsh >/dev/null 2>&1 || return 0
  [ -n "${PS1:-}" ] || return 0
  [ -n "${LAB_EFS_TCSH_ACTIVE:-}" ] && return 0
  case "$(whoami 2>/dev/null)" in
    root|centos|ec2-user|ssm-user|cloud-user|ubuntu|admin) return 0 ;;
  esac
  case "$(ps -o comm= -p $$ 2>/dev/null | tr -d ' \n')" in
    bash|sh|dash) ;;
    *) return 0 ;;
  esac
  export LAB_EFS_TCSH_ACTIVE=1
  exec /bin/tcsh -l
}
lab_efs_tools_profile_sh
ZZLABEFS
  chmod 644 /etc/profile.d/zz-lab-efs-tools.sh

  # Proven on live lab VM: no bash redirects in tcsh backticks, no nested else-if.
  cat >/etc/profile.d/zz-lab-efs-tools.csh <<'ZZLABEFSCSH'
# semiconlabs learner tcsh env
set _lab_user = `sh -c 'whoami 2>/dev/null'`
if ( "$_lab_user" == "root" ) goto lab_efs_done
if ( "$_lab_user" == "centos" ) goto lab_efs_done
if ( "$_lab_user" == "ec2-user" ) goto lab_efs_done
if ( "$_lab_user" == "ssm-user" ) goto lab_efs_done
if ( "$_lab_user" == "cloud-user" ) goto lab_efs_done
if ( "$_lab_user" == "ubuntu" ) goto lab_efs_done
if ( "$_lab_user" == "admin" ) goto lab_efs_done

# Black-screen fix: DCV virtual sessions start the desktop via non-interactive
# login tcsh (dcvsessioninit → Xclients). Sourcing pdsource there can hang for
# a long time on NFS (e.g. find MODUS under /PD/cdn) so XFCE never starts and
# the browser shows a black DCV canvas. Load tool env only in interactive
# terminals (XFCE Terminal / lab-login-shell have a prompt + tty).
if ( ! $?prompt ) goto lab_efs_done
set _lab_tty = `sh -c 'tty 2>/dev/null || true'`
if ( "$_lab_tty" == "not a tty" ) goto lab_efs_done
if ( "$_lab_tty" == "" ) goto lab_efs_done

if ( ! $?_LAB_EFS_TOOLS_LOADED ) then
  set _LAB_EFS_TOOLS_LOADED
  set _orig_dir = "$cwd"

  if ( ! -r /etc/lab/efs-tool-sources.lst ) then
    sh -c 'install -d /etc/lab; : >/etc/lab/efs-tool-sources.lst; for p in /data/tools/pdsource /data/tools/PD/pdsource /data/tools/alsource /data/tools/AL/alsource /data/tools/dvsource /data/tools/DV/dvsource; do [ -f "$p" ] && echo "$p" >>/etc/lab/efs-tool-sources.lst; done; cp -f /etc/lab/efs-tool-sources.lst /etc/lab/efs-tool-sources.raw.lst 2>/dev/null || true' >& /dev/null
  endif

  if ( ! $?MODUSHOME ) setenv MODUSHOME ""
  if ( ! $?JOULES_HOME ) setenv JOULES_HOME ""
  if ( ! $?CDS_INST_DIR ) setenv CDS_INST_DIR ""
  if ( ! $?CDS_ROOT ) setenv CDS_ROOT ""

  # Interactive: cd to actual tool path then source (no /PD|/DV|/AL shortcuts).
  if ( -r /etc/lab/efs-tool-sources.lst ) then
    foreach f (`grep -v '^[[:space:]]*#' /etc/lab/efs-tool-sources.lst | grep -v '^[[:space:]]*$'`)
      if ( -f "$f" ) then
        if ( "$f" =~ *pdsource* ) then
          if ( -d /data/tools/PD ) then
            cd /data/tools/PD
          endif
        endif
        if ( "$f" =~ *alsource* ) then
          if ( -d /data/tools/AL ) then
            cd /data/tools/AL
          endif
        endif
        if ( "$f" =~ *dvsource* || "$f" =~ *cdnsource* ) then
          if ( -d /data/tools/DV ) then
            cd /data/tools/DV
          endif
        endif
        source "$f"
      endif
    end
  endif

  if ( $?ICC2_HOME ) then
    if ( "$ICC2_HOME" != "" ) then
      if ( -d "$ICC2_HOME/linux64/bin" ) set path = ( "$ICC2_HOME/linux64/bin" $path )
      if ( -d "$ICC2_HOME/bin" ) set path = ( "$ICC2_HOME/bin" $path )
    endif
  endif

  if ( $?prompt ) set prompt = '%{\033[32m%}%n@%m(%n):[...%~]$%{\033[0m%} '

  set _lab_home = `sh -c 'getent passwd "$USER" 2>/dev/null | cut -d: -f6'`
  if ( "$_lab_home" != "" ) then
    if ( -d "$_lab_home" ) cd "$_lab_home"
  endif
  if ( "$cwd" == "$_orig_dir" ) then
    if ( $?HOME ) cd "$HOME"
  endif
endif

lab_efs_done:
ZZLABEFSCSH
  chmod 644 /etc/profile.d/zz-lab-efs-tools.csh

  # Futurense Labs — every lab (alias usable after FSx /data mount)
  cat >/etc/profile.d/zz-futurense-lab-setup.csh <<'FUTTCSH'
# semiconlabs-futurense-lab-setup — Futurense project bootstrap (after FSx /data mount)
if ( ! $?semiconlabs_futurense_lab_setup ) then
  set semiconlabs_futurense_lab_setup = 1
  alias futurense_lab_setup 'bash /data/futurense_modules/setup_project.sh'
endif
FUTTCSH
  chmod 644 /etc/profile.d/zz-futurense-lab-setup.csh

  for skel_rc in .tcshrc .cshrc; do
    if [ ! -f /etc/skel/$skel_rc ] || ! grep -qF 'semiconlabs-lab-efs-tool-env' /etc/skel/$skel_rc 2>/dev/null; then
      printf '%s\n' '# semiconlabs-lab-efs-tool-env' \
        'if ( -r /etc/profile.d/zz-lab-efs-tools.csh ) source /etc/profile.d/zz-lab-efs-tools.csh' \
        >>/etc/skel/$skel_rc
    fi
    if [ ! -f /etc/skel/$skel_rc ] || ! grep -qF 'semiconlabs-futurense-lab-setup' /etc/skel/$skel_rc 2>/dev/null; then
      printf '%s\n' '# semiconlabs-futurense-lab-setup' \
        'if ( -r /etc/profile.d/zz-futurense-lab-setup.csh ) source /etc/profile.d/zz-futurense-lab-setup.csh' \
        >>/etc/skel/$skel_rc
    fi
  done
  if [ -f /etc/skel/.bashrc ]; then
    sed -i '/zz-lab-efs-tools\.csh/d;/zz-futurense-lab-setup\.csh/d' /etc/skel/.bashrc 2>/dev/null || true
  fi
  if [ ! -f /etc/skel/.bashrc ] || ! grep -qF 'semiconlabs-lab-efs-tool-env' /etc/skel/.bashrc 2>/dev/null; then
    printf '%s\n' '' '# semiconlabs-lab-efs-tool-env' \
      'if [ -r /etc/profile.d/zz-lab-efs-tools.sh ]; then . /etc/profile.d/zz-lab-efs-tools.sh; fi' \
      >>/etc/skel/.bashrc
  fi
  if [ -f /etc/csh.cshrc ] && ! grep -qF 'semiconlabs-lab-efs-tool-env' /etc/csh.cshrc 2>/dev/null; then
    printf '%s\n' '# semiconlabs-lab-efs-tool-env' \
      'if ( -r /etc/profile.d/zz-lab-efs-tools.csh ) source /etc/profile.d/zz-lab-efs-tools.csh' \
      >>/etc/csh.cshrc
  fi
  if [ -f /etc/csh.cshrc ] && ! grep -qF 'semiconlabs-futurense-lab-setup' /etc/csh.cshrc 2>/dev/null; then
    printf '%s\n' '# semiconlabs-futurense-lab-setup' \
      'if ( -r /etc/profile.d/zz-futurense-lab-setup.csh ) source /etc/profile.d/zz-futurense-lab-setup.csh' \
      >>/etc/csh.cshrc
  fi
  install -d /etc/skel/.config/xfce4/terminal
  cat >/etc/skel/.config/xfce4/terminal/terminalrc <<'EOF'
[Configuration]
CommandLoginShell=TRUE
RunCustomCommand=TRUE
CustomCommand=/usr/local/bin/lab-login-shell
EOF
}

lab_pd_ensure_eda_x11_libs() {
  # Rocky/EL9 GUI AMI often omits libXss; Synopsys icc2_shell needs libXss.so.1.
  if [ -e /usr/lib64/libXss.so.1 ] || [ -e /lib64/libXss.so.1 ]; then
    lab_pd_log "EDA X11 libs: libXss.so.1 already present"
    return 0
  fi
  lab_pd_log "EDA X11 libs: installing libXScrnSaver (and related) for icc2_shell"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y libXScrnSaver motif mesa-libGLU libnsl 2>&1 | tail -20 | tee -a "$LOG" || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y libXScrnSaver motif mesa-libGLU libnsl 2>&1 | tail -20 | tee -a "$LOG" || true
  fi
  if [ -e /usr/lib64/libXss.so.1 ] || [ -e /lib64/libXss.so.1 ]; then
    lab_pd_log "EDA X11 libs: libXss.so.1 OK"
  else
    lab_pd_log "WARN EDA X11 libs: libXss.so.1 still missing (rebake AMI or fix yum repos)"
  fi
}

lab_pd_install_login_shell
lab_pd_ensure_eda_x11_libs
lab_pd_rebuild_filtered_lst
lab_pd_install_profile_hooks
if [ -n "${1:-}" ]; then
  lab_pd_patch_one_home "$1" || true
else
  lab_pd_patch_home_rcs || true
fi
lab_pd_log "harden complete"
exit 0
