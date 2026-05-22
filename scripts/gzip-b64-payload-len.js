#!/usr/bin/env node
/**
 * Terraform external data: decode user_data_base64 (gzip) and report byte length.
 * EC2 limit is 16384 bytes on the payload before cloud-init base64 handling.
 */
'use strict';

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  input += chunk;
});
process.stdin.on('end', () => {
  const out = (payload) => {
    process.stdout.write(JSON.stringify(payload));
  };
  try {
    const q = JSON.parse(input || '{}');
    const buf = Buffer.from(String(q.b64 || ''), 'base64');
    const len = buf.length;
    const gzip = len >= 2 && buf[0] === 0x1f && buf[1] === 0x8b;
    const ok = len > 0 && len <= 16384;
    out({
      len: String(len),
      ok: ok ? 'true' : 'false',
      gzip: gzip ? 'true' : 'false',
    });
  } catch (e) {
    out({
      len: '0',
      ok: 'false',
      gzip: 'false',
      error: String(e && e.message ? e.message : e),
    });
  }
});
