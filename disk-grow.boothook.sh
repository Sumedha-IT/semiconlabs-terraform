#!/bin/bash
# Early disk grow (AMI: / on xvda4|nvme0n1p4 ~15G; /home on xvdb ~10G fstab). Idempotent.
exec >>/var/log/lab-disk-grow.log 2>&1
echo "[$(date -u +%FT%TZ)] disk-grow start: $(df -h / 2>/dev/null | tail -1)"
rm -rf /var/log/pcp/pmlogger/* 2>/dev/null || true
grow_fs() {
  local mp="$1" s f; s=$(findmnt -n -o SOURCE --target "$mp" 2>/dev/null) || return 0
  f=$(findmnt -n -o FSTYPE --target "$mp" 2>/dev/null) || return 0
  case "$f" in xfs) xfs_growfs "$mp" 2>/dev/null || true ;; ext*) resize2fs "$s" 2>/dev/null || true ;; esac
}
# Prefer partition 4 (new AMI); else LVM p2 (legacy).
if [ -b /dev/nvme0n1p4 ]; then growpart /dev/nvme0n1 4 2>/dev/null || true; grow_fs /
elif [ -b /dev/xvda4 ]; then growpart /dev/xvda 4 2>/dev/null || true; grow_fs /
elif [ -b /dev/nvme0n1p2 ]; then
  growpart /dev/nvme0n1 2 2>/dev/null || true
  pvresize /dev/nvme0n1p2 2>/dev/null || true
  lvs /dev/cl/root >/dev/null 2>&1 && lvextend -r -l +100%FREE /dev/cl/root 2>/dev/null || true
fi
findmnt -n /home >/dev/null 2>&1 || { mkdir -p /home; mount /home 2>/dev/null || mount -a 2>/dev/null || true; }
findmnt -n /home >/dev/null 2>&1 && grow_fs /home
echo "[$(date -u +%FT%TZ)] disk-grow done: $(df -h / 2>/dev/null | tail -1)"
