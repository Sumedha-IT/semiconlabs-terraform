# Provider-free user-data render for the EC2-API provisioner.
#
# Produces the SAME base64 multipart cloud-init user-data as the full staging-labs-tf
# (../main.tf  data.cloudinit_config.lab.rendered), but with ONLY the tiny `cloudinit` provider —
# no ~600MB aws provider load. The EC2-API worker renders user-data cheaply here, builds the
# launch spec in code, and launches via SDK RunInstances. It reuses the SAME .tftpl files in the
# parent dir, so the rendered bytes are identical to terraform's user_data_base64.
#
# Run (backend does this after cloning + PATCHING the repo's user-data.sh.tftpl):
#   cd render-userdata
#   terraform init -input=false
#   terraform apply -auto-approve -input=false -var-file=../terraform.tfvars
#   terraform output -raw user_data_base64
#
# IMPORTANT: keep the locals below in sync with ../main.tf (lab_user_data_template_vars +
# cloudinit_config). Validate byte-equivalence: diff this output against the full plan's
# user_data_base64 (see README.md).

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.0"
    }
  }
}

locals {
  lower_ad_domain = lower(var.ad_domain)
  ad_krb5_realm   = upper(var.ad_domain)

  # Keep in sync with ../main.tf
  # Avoid regexreplace() — some lab-worker Terraform builds do not expose it.
  lab_env_label = startswith(lower(var.lab_environment), "prod") ? "prod" : "staging"
  lab_username_raw = lower(element(concat(split("@", trimspace(var.lab_username)), [""]), 0))
  lab_username_label = replace(replace(replace(replace(replace(replace(replace(
    local.lab_username_raw,
    ".", ""), "_", ""), "-", ""), "+", ""), " ", ""), "/", ""), "@", "")
  lab_instance_display_name = trimspace(var.lab_username) != "" && local.lab_username_label != "" ? (
    "slabs-${local.lab_env_label}-${var.suffix}-${local.lab_username_label}"
  ) : "slabs-${local.lab_env_label}-instance-${var.suffix}"

  lab_lustre_userdata_inc = trimspace(var.lab_fsx_lustre_dns) != "" ? templatefile("${path.module}/../lab-lustre-userdata.inc.tftpl", {
    lab_fsx_lustre_dns        = var.lab_fsx_lustre_dns
    lab_fsx_lustre_mount_name = var.lab_fsx_lustre_mount_name
    lab_efs_tools_mount_codes = var.lab_efs_tools_mount_codes
    lab_efs_open_tool_execute = var.lab_efs_open_tool_execute
  }) : ""

  lab_user_data_template_vars = {
    aws_region                                = var.aws_region
    suffix                                    = var.suffix
    enable_ad_join                            = var.enable_ad_join
    ad_join_mechanism                         = var.ad_join_mechanism
    ad_domain                                 = var.ad_domain
    ad_krb5_realm                             = local.ad_krb5_realm
    lower_ad_domain                           = local.lower_ad_domain
    ad_extra_upn_suffixes                     = var.ad_extra_upn_suffixes
    ad_join_user                              = var.ad_join_user
    ad_join_password_b64                      = trimspace(var.ad_join_password) != "" ? base64encode(var.ad_join_password) : ""
    ad_join_password_ssm_parameter_name       = var.ad_join_password_ssm_parameter_name
    ad_join_password_secretsmanager_secret_id = var.ad_join_password_secretsmanager_secret_id
    ad_computer_ou                            = var.ad_computer_ou
    ad_dns_ips                                = var.ad_dns_ips
    dcv_use_console_sessions                  = var.dcv_use_console_sessions
    dcv_web_listen_all                        = var.dcv_web_listen_all
    ad_ssm_join_wait_max_sec                  = var.ad_ssm_join_wait_max_sec
    ad_ssm_association_delay                  = var.ad_ssm_association_delay
    ad_sssd_default_shell                     = var.ad_sssd_default_shell
    ad_fallback_adcli_after_ssm               = var.ad_fallback_adcli_after_ssm
    lab_lustre_userdata_inc                   = local.lab_lustre_userdata_inc
    lab_efs_nfs_host                          = var.lab_efs_nfs_host
    lab_efs_tools_mount_codes                 = var.lab_efs_tools_mount_codes
    lab_efs_aws_ip_fallback                   = var.lab_efs_aws_ip_fallback
    lab_efs_mount_target_ip                   = var.lab_efs_mount_target_ip
    lab_efs_tool_profile_b64                  = var.lab_efs_tool_profile_b64
    lab_efs_open_tool_execute                 = var.lab_efs_open_tool_execute
    # SSH public key is injected via SSM after boot — never embed in user-data (size).
    lab_ssh_public_key_b64    = ""
    enable_ebs_autoresize     = var.enable_ebs_autoresize
  }

  lab_user_data_rendered = templatefile("${path.module}/../user-data.sh.tftpl", merge(local.lab_user_data_template_vars, {
    lab_efs_tool_profile_b64 = ""
    lab_environment          = var.lab_environment
    lab_bootstrap_log_group  = var.lab_bootstrap_log_group
    lab_monitoring_enabled   = var.lab_monitoring_enabled
    enable_ebs_autoresize    = var.enable_ebs_autoresize
    lab_bootstrap_monitoring_script = var.lab_monitoring_enabled ? templatefile("${path.module}/../lab-bootstrap-monitoring.sh.tftpl", {
      aws_region                = var.aws_region
      lab_bootstrap_log_group   = var.lab_bootstrap_log_group
      lab_environment           = var.lab_environment
      lab_health_log_group      = var.lab_health_log_group
      lab_health_interval_min   = var.lab_health_interval_min
      lab_health_mem_alert_pct  = var.lab_health_mem_alert_pct
      lab_health_disk_alert_pct = var.lab_health_disk_alert_pct
    }) : ""
  }))

  lab_disk_grow_boothook = file("${path.module}/../disk-grow.boothook.sh")
}

# Same multipart user-data terraform builds in ../main.tf (boothook + bootstrap), gzip+base64.
data "cloudinit_config" "lab" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-boothook"
    filename     = "00-disk-grow.sh"
    content      = local.lab_disk_grow_boothook
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "10-lab-bootstrap.sh"
    content      = local.lab_user_data_rendered
  }
}

output "user_data_base64" {
  value = data.cloudinit_config.lab.rendered
}

output "instance_display_name" {
  value = local.lab_instance_display_name
}

# EC2 RunInstances launch spec, resolved by terraform (so variable DEFAULTS apply — e.g.
# lab_security_group_id when the backend doesn't pass it). Mirrors ../main.tf aws_instance +
# parsePlannedEc2LaunchSpec. Backend reads this instead of the raw JS variables object.
output "launch_spec" {
  value = jsonencode({
    amiId                         = var.ami_id
    instanceType                  = var.instance_type
    subnetId                      = var.subnet_id
    securityGroupIds              = [var.lab_security_group_id]
    iamInstanceProfileName        = var.iam_instance_profile_name
    associatePublicIpAddress      = var.associate_public_ip_address
    rootVolumeSizeGb              = var.root_volume_size
    deleteRootVolumeOnTermination = var.delete_root_volume_on_termination
    tags = merge(
      {
        Name           = local.lab_instance_display_name
        Environment    = var.env_tag
        LabEnvironment = var.lab_environment
        "map-migrated" = "DADS45OSDL"
        LabBootstrap   = "PENDING"
      },
      var.enable_ebs_autoresize ? { AutoResize = "true" } : {},
    )
    enableAdJoin          = var.enable_ad_join
    adJoinMechanism       = var.ad_join_mechanism
    adDirectoryId         = var.ad_directory_id
    adDomain              = var.ad_domain
    adSsmJoinDnsIp        = length(var.ad_dns_ips) > 0 ? trimspace(var.ad_dns_ips[0]) : ""
    adSsmAssociationDelay = var.ad_ssm_association_delay
    displayName           = local.lab_instance_display_name
  })
}
