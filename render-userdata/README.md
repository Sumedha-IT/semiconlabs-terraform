# render-userdata — provider-free user-data render (EC2-API CPU win)

The EC2-API provisioner (`LAB_PROVISION_ENGINE=ec2_api`) renders the lab user-data here with
**only the `cloudinit` provider** — no ~600 MB aws provider — then builds the `RunInstances`
launch spec in code. This cuts the worker's CPU per lab from ~1 vCPU (full terraform) to ~0.2 vCPU.

It reuses the **same** `../user-data.sh.tftpl`, `../lab-lustre-userdata.inc.tftpl`,
`../lab-bootstrap-monitoring.sh.tftpl`, `../disk-grow.boothook.sh`, and the same var mapping /
`cloudinit_config` as `../main.tf`, so the rendered `user_data_base64` is identical to what the
full terraform produces.

## How the backend uses it
After cloning + patching the repo and writing `../terraform.tfvars`, the worker runs (in this dir):

```bash
terraform init  -input=false
terraform apply -auto-approve -input=false -var-file=../terraform.tfvars
terraform output -raw user_data_base64
```

Toggle: `LAB_EC2_API_PROVIDERLESS_RENDER=false` falls back to the terraform plan-parse path.

## Validate byte/functional equivalence (do this once after changing templates)
```bash
# provider-free render:
cd render-userdata && terraform init && \
  terraform apply -auto-approve -var-file=../terraform.tfvars && \
  terraform output -raw user_data_base64 | base64 -d | gunzip > /tmp/render.mime

# full terraform (aws provider) — same vars:
cd .. && terraform init && terraform plan -out=/tmp/p.tfplan && \
  terraform show -json /tmp/p.tfplan | \
  jq -r '.resource_changes[]|select(.type=="aws_instance").change.after.user_data_base64' \
  | base64 -d | gunzip > /tmp/full.mime

diff /tmp/render.mime /tmp/full.mime && echo "IDENTICAL"
```

## Keep in sync
`main.tf` locals here mirror `../main.tf` (`lab_user_data_template_vars` + `cloudinit_config`);
`variables.tf` mirrors `../variables.tf`. Update both when the parent template vars change.
