#!/usr/bin/env bash
# CI / ECS: ensure gzip payload (after base64 decode) is <= 16384 bytes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
terraform init -input=false >/dev/null
terraform validate -no-color
B64="$(echo 'local.lab_user_data_gzip_b64' | terraform console -var="suffix=ci" -var="instance_name=ci" 2>/dev/null | tr -d '"')"
LEN="$(printf '%s' "$B64" | base64 -d 2>/dev/null | wc -c | tr -d ' ')"
echo "user-data gzip payload: ${LEN} bytes (max 16384)"
if [ "${LEN:-0}" -gt 16384 ]; then
  echo "ERROR: gzip payload exceeds EC2 user-data limit" >&2
  exit 1
fi
exit 0
