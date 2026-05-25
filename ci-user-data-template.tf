# CI / pre-apply: ensures user-data.sh.tftpl renders (catches unescaped ${bash} in heredocs).
# Run: terraform init && terraform validate
#      terraform console -var="suffix=ci" -var="instance_name=ci" -non-interactive
#      > length(local.ci_user_data_rendered)
locals {
  ci_user_data_rendered      = templatefile("${path.module}/user-data.sh.tftpl", {
    aws_region                            = var.aws_region
    suffix                                = var.suffix
    enable_ad_join                        = var.enable_ad_join
    ad_join_mechanism                     = var.ad_join_mechanism
    ad_domain                             = var.ad_domain
    ad_krb5_realm                         = upper(var.ad_domain)
    lower_ad_domain                       = lower(var.ad_domain)
    ad_extra_upn_suffixes                 = var.ad_extra_upn_suffixes
    ad_join_user                          = var.ad_join_user
    ad_join_password_b64                  = ""
    ad_join_password_ssm_parameter_name   = var.ad_join_password_ssm_parameter_name
    ad_join_password_secretsmanager_secret_id = var.ad_join_password_secretsmanager_secret_id
    ad_computer_ou                        = var.ad_computer_ou
    ad_dns_ips                            = var.ad_dns_ips
    dcv_use_console_sessions              = var.dcv_use_console_sessions
    dcv_web_listen_all                    = var.dcv_web_listen_all
    ad_ssm_join_wait_max_sec              = var.ad_ssm_join_wait_max_sec
    ad_ssm_association_delay              = var.ad_ssm_association_delay
    ad_sssd_default_shell                 = var.ad_sssd_default_shell
    ad_fallback_adcli_after_ssm           = var.ad_fallback_adcli_after_ssm
    lab_efs_nfs_host                      = var.lab_efs_nfs_host
    lab_efs_tools_mount_codes             = var.lab_efs_tools_mount_codes
    lab_efs_aws_ip_fallback               = var.lab_efs_aws_ip_fallback
    lab_efs_mount_target_ip               = var.lab_efs_mount_target_ip
    lab_efs_tool_profile_b64            = var.lab_efs_tool_profile_b64
    lab_efs_open_tool_execute             = var.lab_efs_open_tool_execute
    lab_ssh_public_key_b64                = ""
  })
  ci_user_data_gzip_b64 = base64gzip(local.ci_user_data_rendered)
}

output "ci_user_data_template_bytes" {
  value       = length(local.ci_user_data_rendered)
  description = "Uncompressed templatefile() size (informational; EC2 limit applies to gzip payload)."
}

output "ci_user_data_gzip_b64_chars" {
  value       = length(local.ci_user_data_gzip_b64)
  description = "Wire size of user_data_base64; gzip payload bytes = base64 decode length (see validate-user-data-template.ps1)."
}
