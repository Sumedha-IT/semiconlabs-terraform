# Mirror of ../variables.tf (type + default only). Declares the full parent set so the backend can
# pass the same `-var-file=../terraform.tfvars` here with no undeclared-variable warnings.
# KEEP IN SYNC with ../variables.tf when variables are added/removed.

# --- launch-spec vars (not used by the render; declared so tfvars loads cleanly) ---
variable "instance_name" {
  type    = string
  default = "SumedhaIT"
}
variable "ami_id" {
  type    = string
  default = "ami-0d0ce75b716b54c25"
}
variable "name" {
  type    = string
  default = "Sumedha-CloudLabs_Server"
}
variable "instance_type" {
  type    = string
  default = "m6a.xlarge"
}
variable "root_volume_size" {
  type    = number
  default = 15
}
variable "enable_ebs_autoresize" {
  type    = bool
  default = false
}
variable "delete_root_volume_on_termination" {
  type    = bool
  default = true
}
variable "subnet_id" {
  type    = string
  default = "subnet-0c4d6990bb08a09b2"
}
variable "lab_security_group_id" {
  type    = string
  default = "sg-0223e0bc0c606ef29"
}
variable "iam_instance_profile_name" {
  type    = string
  default = "LabSSMRole"
}
variable "associate_public_ip_address" {
  type    = bool
  default = false
}
variable "env_tag" {
  type    = string
  default = "LABS-STAGING"
}
variable "ad_directory_id" {
  type    = string
  default = "d-9f67755145"
}
variable "enable_ec2_detailed_monitoring" {
  type    = bool
  default = true
}

# --- vars consumed by the user-data templates (render) ---
variable "suffix" {
  type = string
}
variable "lab_username" {
  type    = string
  default = ""
}
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "lab_environment" {
  type    = string
  default = "staging"
}
variable "lab_bootstrap_log_group" {
  type    = string
  default = "/labs/bootstrap/staging"
}
variable "lab_monitoring_enabled" {
  type    = bool
  default = true
}
variable "lab_health_log_group" {
  type    = string
  default = "/labs/bootstrap/staging"
}
variable "lab_health_interval_min" {
  type    = number
  default = 15
}
variable "lab_health_mem_alert_pct" {
  type    = number
  default = 80
}
variable "lab_health_disk_alert_pct" {
  type    = number
  default = 90
}

variable "enable_ad_join" {
  type    = bool
  default = true
}
variable "ad_join_mechanism" {
  type    = string
  default = "realm_userdata"
}
variable "ad_domain" {
  type    = string
  default = "sumedhalabs.com"
}
variable "ad_extra_upn_suffixes" {
  type    = list(string)
  default = ["sumedhait.com", "gmail.com"]
}
variable "ad_join_user" {
  type    = string
  default = "admin"
}
variable "ad_join_password" {
  type      = string
  sensitive = true
  default   = "Sumedhalabs@2026"
}
variable "ad_join_password_ssm_parameter_name" {
  type    = string
  default = "/semiconlabs/lab/ad-join-password"
}
variable "ad_join_password_secretsmanager_secret_id" {
  type    = string
  default = ""
}
variable "ad_computer_ou" {
  type    = string
  default = ""
}
variable "ad_dns_ips" {
  type    = list(string)
  default = ["10.10.149.108", "10.10.136.0"]
}
variable "dcv_use_console_sessions" {
  type    = bool
  default = false
}
variable "dcv_web_listen_all" {
  type    = bool
  default = true
}
variable "ad_ssm_join_wait_max_sec" {
  type    = number
  default = 2700
}
variable "ad_ssm_association_delay" {
  type    = string
  default = "180s"
}
variable "ad_fallback_adcli_after_ssm" {
  type    = bool
  default = false
}
variable "ad_sssd_default_shell" {
  type    = string
  default = "/bin/tcsh"
}

variable "lab_efs_nfs_host" {
  type    = string
  default = ""
}
variable "lab_fsx_lustre_dns" {
  type    = string
  default = "10.50.10.147"
}
variable "lab_fsx_lustre_mount_name" {
  type    = string
  default = "t4zh7bev"
}
variable "lab_efs_tools_mount_codes" {
  type    = list(string)
  default = []
}
variable "lab_efs_aws_ip_fallback" {
  type    = bool
  default = true
}
variable "lab_efs_mount_target_ip" {
  type    = string
  default = "10.10.3.41"
}
variable "lab_efs_tool_profile_b64" {
  type    = string
  default = ""
}
variable "lab_efs_open_tool_execute" {
  type    = bool
  default = true
}
