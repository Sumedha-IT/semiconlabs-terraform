# semiconlabs-terraform (production)

**Production-only** lab EC2 bootstrap. Staging experiments belong in [staging-labs-tf](https://github.com/Sumedha-IT/staging-labs-tf).

| Repo | Fleet |
|------|--------|
| **semiconlabs-terraform** (this repo) | Production (`semiconlabs.com`, prod VPC) |
| staging-labs-tf | Staging (`sumedhalabs.com`, staging VPC) |

## Backend

Prod ECS must clone this repo (default in `lab-domain-mapping.util.ts`). Do **not** point production at the staging repo.

Required backend `.env` overrides are merged at apply time — see `Semiconlabs-backend/.env.production.example` and `buildLabRuntimeTerraformEnvOverrides()` (`LAB_PRIVATE_SUBNET_ID`, `LAB_SECURITY_GROUP_ID`, `AD_DNS_IPS`, join password via SSM, etc.).

## User-data

Monolithic `user-data.sh.tftpl` (gzip, 16 KiB EC2 limit). Plan fails if over limit (`user-data-size.tf`). S3 split (`bootstrap-full.sh.tftpl` + stub) is prepared but commented in `main.tf`.

## DCV hardening (user-data)

New lab instances get from `user-data.sh.tftpl`:

- **Clipboard:** `/etc/dcv/default.perm` blocks client ↔ VM only; in-session copy/paste works
- **Single monitor:** `[display] max-num-heads=1`, `enable-client-resize=true` (fills browser viewport)

Internet egress (VPC endpoints, lab SG rules) is managed in **slabs infra / AWS Console** — not this repo. See `lab-internet-restriction-cli-runbook.md`.

## Local prod-shaped apply

```bash
cp terraform.tfvars.production.example terraform.tfvars
# edit secrets locally only — never commit terraform.tfvars
terraform init
terraform plan -var="suffix=manual-test"
```
