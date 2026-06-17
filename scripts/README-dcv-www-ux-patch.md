# DCV www UX patch (v2) for running lab EC2 instances

## What it does

1. Sets `client-eviction-policy = "reject-new-connection"` (reject 2nd browser; keep 1st tab).
2. Replaces **only** NICE DCV `"Maximum number of clients reached"` with the friendly duplicate-session text.
3. **Reverts** mistaken v1 patch that replaced `"The connection has been closed"` everywhere.
4. Injects `custom-popup.js` (Stop Lab reminder on first opens).

Sessions already use `--max-concurrent-clients 1` from the backend.

## Expected behaviour

| Scenario | DCV message |
|----------|-------------|
| Stop Lab, return to old DCV tab | **The connection has been closed** (original) |
| Open same lab URL in 2nd browser while 1st is active | Custom “already active session…” message |
| First Open Lab | Portal OK dialog + `custom-popup.js` alert (unchanged) |

## Automatic

Deploy backend v2 patch. Reconcile cron / Start Lab runs SSM when `connection_details.dcv_www_ux_patch_v2` is not set (v1 counts as needing upgrade).

`LAB_PATCH_DCV_WWW_UX_ENABLED=false` disables.

## Manual

```powershell
cd semiconlabs-terraform\scripts
.\patch-dcv-www-ux.ps1 -InstanceIds i-xxxxxxxx -Region ap-south-1
```

## New instances

`user-data.sh.tftpl` applies v2 at bootstrap.
