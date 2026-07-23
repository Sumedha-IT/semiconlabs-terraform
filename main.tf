provider "aws" {
  region = "ap-south-1"
}

locals {
  lower_ad_domain = lower(var.ad_domain)
  # Kerberos realm for sssd.conf (CloudLabs DCV guide); matches typical Managed AD DNS name → REALM mapping.
  ad_krb5_realm = upper(var.ad_domain)
  # aws_ssm_association.parameters only accepts string values (not lists). AWS also rejects a single
  # comma-separated value for dnsIpAddresses (validates the whole string as one IPv4).
  # Passing one directory DNS IP satisfies SSM; user-data still applies the full var.ad_dns_ips list
  # to the NIC resolver (nmcli). Put the primary DC DNS first in ad_dns_ips.
  ad_ssm_join_dns_ip = trimspace(var.ad_dns_ips[0])

  # Production-only repo — slabs-prod-{suffix}-{username}
  # Avoid regexreplace() — some lab-worker Terraform builds do not expose it.
  lab_env_label = "prod"
  lab_username_raw = lower(element(concat(split("@", trimspace(var.lab_username)), [""]), 0))
  lab_username_label = replace(replace(replace(replace(replace(replace(replace(
    local.lab_username_raw,
    ".", ""), "_", ""), "-", ""), "+", ""), " ", ""), "/", ""), "@", "")
  lab_instance_display_name = trimspace(var.lab_username) != "" && local.lab_username_label != "" ? (
    "slabs-${local.lab_env_label}-${var.suffix}-${local.lab_username_label}"
  ) : "slabs-${local.lab_env_label}-instance-${var.suffix}"

  # FSx Lustre shared-storage bootstrap block, spliced into user-data when lab_fsx_lustre_dns is set.
  # Empty string => user-data keeps the legacy EFS mount path (lab_efs_nfs_host).
  lab_lustre_userdata_inc = trimspace(var.lab_fsx_lustre_dns) != "" ? templatefile("${path.module}/lab-lustre-userdata.inc.tftpl", {
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
    lab_ssh_public_key_b64 = ""
  }

  # TEMP (prod): monolithic user-data — keep under 16 KiB gzip. Do not embed large per-lab blobs here.
  lab_user_data_rendered = templatefile("${path.module}/user-data.sh.tftpl", merge(local.lab_user_data_template_vars, {
    lab_efs_tool_profile_b64 = ""
    lab_environment          = var.lab_environment
    lab_bootstrap_log_group  = var.lab_bootstrap_log_group
    lab_monitoring_enabled   = var.lab_monitoring_enabled
    lab_bootstrap_monitoring_script = var.lab_monitoring_enabled ? templatefile("${path.module}/lab-bootstrap-monitoring.sh.tftpl", {
      aws_region                = var.aws_region
      lab_bootstrap_log_group   = var.lab_bootstrap_log_group
      lab_environment           = var.lab_environment
      lab_health_log_group      = var.lab_health_log_group
      lab_health_interval_min   = var.lab_health_interval_min
      lab_health_mem_alert_pct  = var.lab_health_mem_alert_pct
      lab_health_disk_alert_pct = var.lab_health_disk_alert_pct
    }) : ""
  }))

  # cloud-boothook: runs EARLY in the cloud-init init stage (before the heavy
  # init/final work), so it executes even when the AMI ships an ~8G LVM root
  # that is already ~99% full. Without this, cloud-init crashes on "No space
  # left on device" while writing its own status, and the main bootstrap
  # (text/x-shellscript part) in cloud-final never runs. We free the stale
  # pcp logs baked into the AMI, then grow the partition + LVM root so the
  # rest of bootstrap has room. growpart/lvextend are idempotent (no-op once
  # the LV already fills the disk), so running on every boot is safe.
  lab_disk_grow_boothook = file("${path.module}/disk-grow.boothook.sh")

  # TODO (post-prod): S3 bootstrap split — see bootstrap-full.sh.tftpl + user-data-stub.sh.tftpl
  # lab_bootstrap_s3_key     = "lab-bootstrap/bootstrap-full-${var.suffix}.sh"
  # lab_bootstrap_s3_uri     = "s3://${var.bootstrap_s3_bucket}/${local.lab_bootstrap_s3_key}"
  # lab_bootstrap_full_rendered = templatefile("${path.module}/bootstrap-full.sh.tftpl", local.lab_user_data_template_vars)
  # lab_user_data_rendered = templatefile("${path.module}/user-data-stub.sh.tftpl", { aws_region = var.aws_region, suffix = var.suffix, bootstrap_s3_uri = local.lab_bootstrap_s3_uri })
  # lab_user_data_gzip_b64 = base64gzip(local.lab_user_data_rendered)
}

# Multipart user-data: boothook (early disk grow) + main bootstrap shell script.
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

# resource "aws_s3_object" "lab_bootstrap_full" {
#   bucket       = var.bootstrap_s3_bucket
#   key          = local.lab_bootstrap_s3_key
#   content      = local.lab_bootstrap_full_rendered
#   content_type = "text/x-shellscript"
#   etag         = md5(local.lab_bootstrap_full_rendered)
#   server_side_encryption = "AES256"
# }

# Generate an SSH key pair
resource "tls_private_key" "master_key_gen" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# No aws_key_pair resource: ec2:ImportKeyPair is often denied. Inject public key via user-data.

# Output the private key content
output "private_key_pem" {
  value     = tls_private_key.master_key_gen.private_key_pem
  sensitive = true
}

# Lab instance (Amazon Linux / DCV); bootstrap enables SSH, EFS, DCV, SSSD
resource "aws_instance" "CentOS8-AMD" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [var.lab_security_group_id]
  iam_instance_profile        = var.iam_instance_profile_name
  monitoring                  = var.enable_ec2_detailed_monitoring

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = var.delete_root_volume_on_termination
  }

  # EC2 user_data gzip payload must be <= 16384 bytes (see user-data-size.tf).
  user_data_base64 = data.cloudinit_config.lab.rendered
  tags = {
    Name           = local.lab_instance_display_name
    Environment    = var.env_tag
    LabEnvironment = var.lab_environment
    map-migrated   = "DADS45OSDL"
    LabBootstrap   = "PENDING"
  }
}

# Let amazon-ssm-agent register with Fleet Manager before attaching JoinDirectoryServiceDomain.
resource "time_sleep" "wait_ssm_registration_after_ec2" {
  depends_on = [aws_instance.CentOS8-AMD]

  create_duration = var.enable_ad_join && var.ad_join_mechanism == "ssm_aws_managed" ? var.ad_ssm_association_delay : "0s"
}

# AWS Managed Microsoft AD: official SSM Automation (no realm join password on the instance).
resource "aws_ssm_association" "managed_ad_domain_join" {
  count = var.enable_ad_join && var.ad_join_mechanism == "ssm_aws_managed" ? 1 : 0

  depends_on = [time_sleep.wait_ssm_registration_after_ec2]

  name             = "AWS-JoinDirectoryServiceDomain"
  association_name = substr("${local.lab_instance_display_name}-ad-join", 0, 128)

  targets {
    key    = "InstanceIds"
    values = [aws_instance.CentOS8-AMD.id]
  }

  parameters = {
    directoryId    = var.ad_directory_id
    directoryName  = var.ad_domain
    dnsIpAddresses = local.ad_ssm_join_dns_ip
  }
}

# Save the private key locally
resource "local_file" "local_key_pair" {
  filename        = "${local.lab_instance_display_name}.pem"
  file_permission = "0400"
  content         = tls_private_key.master_key_gen.private_key_pem
}

# Output the CentOS8-AMD Server Public IP
output "CentOS8_AMD_Server_Public_IP" {
  value = aws_instance.CentOS8-AMD.public_ip
}

# Private IP (required when instance is in a private subnet; backend / reverse proxy use this for SSH/DCV upstream)
output "CentOS8_AMD_Server_Private_IP" {
  value = aws_instance.CentOS8-AMD.private_ip
}

# Output Copy the URL
output "CentOS8_AMD_Login" {
  value = "Copy the mentioned URL & Paste it on Browser https://${aws_instance.CentOS8-AMD.public_ip}:8443"
}

output "pem_file_for_ssh" {
  value     = "${local.lab_instance_display_name}.pem"
  sensitive = false
}

output "instance_id" {
  value = aws_instance.CentOS8-AMD.id
}

# output "lab_bootstrap_s3_uri" { value = local.lab_bootstrap_s3_uri }
# output "lab_bootstrap_full_bytes" { value = nonsensitive(length(local.lab_bootstrap_full_rendered)) }
