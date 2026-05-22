#!/usr/bin/env python3
"""Measure rendered user-data uncompressed vs gzip (EC2 limit: 16384 bytes gzip payload)."""
import base64
import gzip
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def terraform_render() -> bytes:
    proc = subprocess.run(
        ["terraform", "console", "-var=suffix=ci", "-var=instance_name=ci"],
        input="local.ci_user_data_rendered\n",
        capture_output=True,
        text=True,
        cwd=ROOT,
        check=True,
    )
    # console returns a quoted HCL string; strip outer quotes and unescape minimally
    s = proc.stdout.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    return s.encode("utf-8", errors="replace")


def main() -> int:
    raw = terraform_render()
    gz = gzip.compress(raw)
    b64 = base64.b64encode(gz)
    print(f"uncompressed_bytes={len(raw)}")
    print(f"gzip_bytes={len(gz)} (must be <= 16384)")
    print(f"base64_gzip_chars={len(b64)}")
    print(f"ok_gzip_under_limit={len(gz) <= 16384}")
    return 0 if len(gz) <= 16384 else 1


if __name__ == "__main__":
    sys.exit(main())
