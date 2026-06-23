# DCV www UX patch (v3) for running lab EC2 instances

## What it does

1. Sets `client-eviction-policy = "same-user-oldest-connection"` (webapp-like: new DCV browser login evicts the oldest connection for the same owner).
2. Reverts v2 `reject-new-connection` policy and custom duplicate-session message text.
3. Keeps **only** v1 revert fixes for mistaken `"The connection has been closed"` replacements.
4. Injects `custom-popup.js` (Stop Lab reminder on first opens).

Sessions already use `--max-concurrent-clients 1` from the backend.

## Expected behaviour

| Scenario | Result |
|----------|--------|
| DCV active in browser 1, same user logs in via DCV URL in browser 2 | Browser 1 disconnected; browser 2 connects |
| Browser 1 after eviction | **The connection has been closed** (standard DCV) |
| Stop Lab, return to old DCV tab | **The connection has been closed** (original) |
| First Open Lab | Portal OK dialog + `custom-popup.js` alert (unchanged) |

## Automatic

Deploy backend with v3 SSM patch. Reconcile cron / Start Lab runs SSM when `connection_details.dcv_www_ux_patch_v3` is not set (v2-only instances are upgraded).

`LAB_PATCH_DCV_WWW_UX_ENABLED=false` disables.

## Manual

```powershell
cd semiconlabs-terraform\scripts
.\patch-dcv-www-ux.ps1 -InstanceIds i-xxxxxxxx -Region ap-south-1
```

## New instances

`user-data.sh.tftpl` / `bootstrap-full.sh.tftpl` apply v3 at bootstrap (`same-user-oldest-connection`).
