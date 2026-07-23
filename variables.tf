# keypair_name variable removed - now using Terraform-generated keypair
# variable "keypair_name" {
#   description = "EC2's Key Pair"
#   type        = string
#   # default = "Koushal-Manual_Server"
# }

# Instance name for tagging the Windows server
variable "instance_name" {
  description = "EC2 Instance Server Name"
  type        = string
  # default = "DCVTestInstance"
}

variable "ami_id" {
  description = "Lab AMI — ap-south-1 golden image (GNOME+DCV+PAM+Lustre client pre-baked; AD join + SSSD finalize in user-data / SSM). Must ship lustre-client + kernel versionlock or FSx mounts fail with 'lustre kernel module not loaded'."
  type        = string
  default     = "ami-029ab927ae6f71d21"
}

variable "name" {
  # Used for Prefix
  description = "Name tag for the Instance"
  type        = string
  default     = "Sumedha-CloudLabs_Server"
}

variable "instance_type" {
  description = "Instance Type for EC2"
  type        = string
  default     = "m6a.xlarge"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30
}

variable "delete_root_volume_on_termination" {
  description = "When false (dedicated labs), root EBS persists after EC2 terminates for retention/backup SKU"
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "Subnet ID where lab EC2 is launched. Prod: subnet-095905a6af90f3c5c (lab-private-1, no NAT). Override via backend LAB_PRIVATE_SUBNET_ID."
  type        = string
  default     = ""
}

variable "lab_security_group_id" {
  description = "Security group attached to lab EC2. Prod: sg-0addb5436378bc42a (lab-only-sg). Override via backend LAB_SECURITY_GROUP_ID."
  type        = string
  default     = ""
}

variable "iam_instance_profile_name" {
  description = "EC2 instance profile for SSM / AD join / EFS API (e.g. slabs-prod-labssmRole)."
  type        = string
  default     = ""
}

variable "associate_public_ip_address" {
  description = "Whether to attach a public IPv4 address to the lab instance"
  type        = bool
  default     = false
}

# key_name variable removed - now using Terraform-generated keypair
# variable "key_name" {
#   description = "Existing EC2 keypair name"
#   type        = string
# }

variable "suffix" {
  description = "Suffix for the variables"
  type        = string
  # default = "Koushal-Manual_"
}

variable "lab_username" {
  description = "Portal/DCV owner username (email or UPN). Used in EC2 Name tag: slabs-prod-{suffix}-{username}."
  type        = string
  default     = ""
}

# Kept for backend tfvars compatibility; must stay production in this repository.
variable "lab_environment" {
  description = "Must be production (staging fleet uses staging-labs-tf)."
  type        = string
  default     = "production"

  validation {
    condition     = var.lab_environment == "production"
    error_message = "lab_environment must be production in semiconlabs-terraform. Use staging-labs-tf for staging labs."
  }
}

variable "lab_bootstrap_log_group" {
  description = "CloudWatch log group for lab VM bootstrap logs (Phase 2 monitoring)."
  type        = string
  default     = "/labs/bootstrap/production"
}

variable "lab_monitoring_enabled" {
  description = "Upload bootstrap log tail + CloudWatch metrics at end of user-data."
  type        = bool
  default     = true
}

variable "enable_ec2_detailed_monitoring" {
  description = "Enable EC2 detailed monitoring (1-min CPU/network metrics, ~$2.30/VM/month)."
  type        = bool
  default     = true
}

variable "lab_health_log_group" {
  description = "CloudWatch log group for periodic guest health snapshots (defaults to bootstrap log group)."
  type        = string
  default     = "/labs/bootstrap/production"
}

variable "lab_health_interval_min" {
  description = "Guest health snapshot interval (minutes). 15 keeps log/metric cost low at scale."
  type        = number
  default     = 15
}

variable "lab_health_mem_alert_pct" {
  description = "Guest [LabHealthAlert] when memory used percent >= this."
  type        = number
  default     = 80
}

variable "lab_health_disk_alert_pct" {
  description = "Guest [LabHealthAlert] when root disk used percent >= this."
  type        = number
  default     = 90
}

variable "env_tag" {
  description = "EC2 ENV tag value (backend sets LABS-PROD; patched into instance tags at apply time)."
  type        = string
  default     = "LABS-PROD"
}

variable "aws_region" {
  description = "Region for aws CLI in user-data (tags, SSM). Matches Semiconlabs-backend .env AWS_REGION."
  type        = string
  default     = "ap-south-1"
}

# Unused until S3 split is enabled in main.tf (kept so backend tfvars do not fail).
variable "bootstrap_s3_bucket" {
  description = "Reserved for S3 bootstrap split (TODO). Not used while main.tf uses monolithic user-data.sh.tftpl."
  type        = string
  default     = ""
}

# AWS Managed Microsoft AD directory id (same as AD_DIRECTORY_ID in Semiconlabs-backend .env).
variable "ad_directory_id" {
  description = "Directory Service id (d-xxxxxxxxxx). Required when enable_ad_join=true and ad_join_mechanism=ssm_aws_managed."
  type        = string
  default     = ""
}

variable "ad_join_mechanism" {
  description = <<-EOT
    ssm_aws_managed — Terraform creates aws_ssm_association with document AWS-JoinDirectoryServiceDomain (no join password on the instance). Can fail when the document's AWS CLI resolves the wrong region on the guest.
    realm_userdata — CloudLabs NICE DCV + AD guide (lab-docs/_dcv_doc_snippet.txt): user-data runs Step 4.4 **adcli join** (password from Terraform base64, SSM, or Secrets) then Step 4.5 **sssd.conf** as documented — not `realm join`.
    Default in this repo is realm_userdata so labs work without the managed SSM document.
    Override per environment in terraform.tfvars or via backend env LAB_AD_JOIN_MECHANISM / AD_JOIN_MECHANISM.
  EOT
  type        = string
  default     = "realm_userdata"

  validation {
    condition     = contains(["ssm_aws_managed", "realm_userdata"], var.ad_join_mechanism)
    error_message = "ad_join_mechanism must be ssm_aws_managed or realm_userdata."
  }
}

# Per-instance AD join (do not bake join into golden AMI).
variable "enable_ad_join" {
  description = "If true, join this instance to the directory (SSM document for Managed AD, or CloudLabs adcli+sssd in user-data when ad_join_mechanism=realm_userdata)."
  type        = bool
  default     = true

  validation {
    condition = !var.enable_ad_join || (
      (var.ad_join_mechanism == "realm_userdata" &&
        var.ad_domain != "" &&
        var.ad_join_user != "" &&
        (trimspace(var.ad_join_password) != "" ||
          var.ad_join_password_secretsmanager_secret_id != "" ||
      var.ad_join_password_ssm_parameter_name != "")) ||
      (var.ad_join_mechanism == "ssm_aws_managed" &&
        var.ad_directory_id != "" &&
        var.ad_domain != "" &&
        length(var.ad_dns_ips) > 0 &&
        (
          !var.ad_fallback_adcli_after_ssm ||
          (var.ad_join_user != "" &&
            (trimspace(var.ad_join_password) != "" ||
              var.ad_join_password_secretsmanager_secret_id != "" ||
          var.ad_join_password_ssm_parameter_name != ""))
      ))
    )
    error_message = "When enable_ad_join=true: realm_userdata needs ad_join_user + password (ad_join_password in tfvars, or Secrets Manager id, or SSM parameter name). ssm_aws_managed needs ad_directory_id + ad_domain + ad_dns_ips; if ad_fallback_adcli_after_ssm=true also set ad_join_user + a password source."
  }
}

variable "ad_domain" {
  description = "AD DNS domain / Kerberos realm name. Matches AD_DOMAIN in Semiconlabs-backend .env (production: semiconlabs.com)."
  type        = string
  default     = "semiconlabs.com"
}

variable "ad_extra_upn_suffixes" {
  description = "Alternate portal UPN DNS suffixes mapped to the forest Kerberos realm in guest /etc/krb5.conf (e.g. gmail.com for user@gmail.com logon)."
  type        = list(string)
  default     = ["sumedhait.com", "gmail.com"]
}

variable "ad_join_user" {
  description = <<-EOT
    Account used for domain join. Use the **sAMAccountName** (e.g. delegated slabs-user) or UPN with **Kerberos realm**
    (e.g. slabs-user@SUMEDHALABS.COM). Avoid user@sumedhalabs.com with adcli/realm on RHEL8 — you may get
    "KDC reply did not match expectations". For AWS Managed Microsoft AD, the customer **Admin** account SAM is
    **admin** (broad OU rights; prefer a Joiners-only user when you can delegate). Non-admin accounts must be
    allowed to create computer objects in the target OU or join fails with userAccountControl / insufficient access.
    EOT
  type        = string
  default     = "admin"
}

variable "ad_join_password" {
  description = <<-EOT
    Plaintext domain-join password (realm_userdata and ad_fallback_adcli). When non-empty, user-data uses this
    instead of reading SSM/Secrets (no instance IAM needed for GetParameter). SECURITY: stored in Terraform state
    and embedded (base64) in EC2 user_data — prefer empty + SSM/Secrets in production; rotate if committed to git.
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "ad_join_password_ssm_parameter_name" {
  description = "realm_userdata: SSM SecureString name for the join account password. Instance profile (e.g. LabSSMRole) needs ssm:GetParameter on this name and kms:Decrypt if the key is not aws/ssm."
  type        = string
  default     = "/semiconlabs/lab/ad-join-password"
}

variable "ad_join_password_secretsmanager_secret_id" {
  description = <<-EOT
    Only for realm_userdata: Secrets Manager secret id or full ARN (plain string password, or JSON with key "password").
    Not used for ssm_aws_managed (AWS-JoinDirectoryServiceDomain does not need this user/password).
    Instance IAM (e.g. LabSSMRole) needs secretsmanager:GetSecretValue on this secret.
  EOT
  type        = string
  default     = ""
}

variable "ad_computer_ou" {
  description = "Optional LDAP OU for computer objects, e.g. OU=Labs,DC=sumedhalabs,DC=com. Leave \"\" to use directory default Computers container."
  type        = string
  default     = ""
}

variable "ad_dns_ips" {
  description = <<-EOT
    AD DNS IP addresses (usually both domain controllers).
    Order matters for SSM domain join: index 0 must be a single valid IPv4 sent to AWS-JoinDirectoryServiceDomain
    (Terraform cannot pass multiple values in parameters; comma-join is rejected by AWS). Remaining entries
    are still applied on the instance resolver via user-data.
  EOT
  type        = list(string)
  default     = []
}

variable "dcv_use_console_sessions" {
  description = "Reserved / diagnostic only (logged in user-data). Backend runs: dcv create-session '<id>' --owner '…' --user '…' --type virtual|console. Default app type is virtual (LAB_DCV_SESSION_TYPE). dcv.conf uses create-session=false at boot."
  type        = bool
  default     = false
}

variable "dcv_web_listen_all" {
  description = "If true, add web-listen-endpoints 0.0.0.0:8443 + disable QUIC in /etc/dcv/dcv.conf (browser access)."
  type        = bool
  default     = true
}

variable "ad_ssm_join_wait_max_sec" {
  description = "When ad_join_mechanism=ssm_aws_managed, poll up to this many seconds for join (SSM Automation runs after boot)."
  type        = number
  default     = 2700
}

variable "ad_ssm_association_delay" {
  description = <<-EOT
    After EC2 enters running state, pause before attaching the SSM association
    AWS-JoinDirectoryServiceDomain. Association creation before amazon-ssm-agent registers with Fleet
    Manager often results in join never reaching the instance (empty realm list, sssd domains=).
    EOT
  type        = string
  default     = "180s"
}

variable "ad_fallback_adcli_after_ssm" {
  description = <<-EOT
    When true and ad_join_mechanism=ssm_aws_managed: if realm/sssd never show an AD domain after AWS-JoinDirectoryServiceDomain,
    run adcli join (manual path from CloudLabs DCV guide) using ad_join_user + SSM/Secrets credentials.
    Requires instance IAM permission to read the secret or parameter (e.g. LabSSMRole + kms decrypt).
    EOT
  type        = bool
  default     = false
}

variable "ad_sssd_default_shell" {
  description = <<-EOT
    SSSD `default_shell` and `override_shell` (interactive login for DCV/SSH when AD loginShell is empty or /bin/false).
    Default `/bin/tcsh` for Cadence-style c-shell labs; user-data installs the `tcsh` package when the path contains `tcsh`.
    Override in terraform.tfvars, domain `terraform_variables`, or backend `LAB_AD_SSSD_DEFAULT_SHELL`.
  EOT
  type        = string
  default     = "/bin/tcsh"
}

# EFS NFS host (DNS only, no ":/" suffix). User-data mounts nfs4 host:/ once to /efs (EFS does not export subpaths as separate NFS roots).
variable "lab_efs_nfs_host" {
  type        = string
  default     = "fs-0985e64c096c42f09.efs.ap-south-1.amazonaws.com"
  description = "EFS filesystem DNS name for lab mounts (same region as instance). Empty string skips all EFS logic in user-data. Ignored when lab_fsx_lustre_dns is set (Lustre takes precedence; EFS is the rollback path)."
}

# FSx for Lustre (shared PROD tool storage) — the prod default. user-data mounts Lustre at /efs
# (not EFS/NFS) and binds /PD|/DV|/AL + /tools the same way. Prod slabs FSx = fs-09f8ba285ecf05b0e,
# mount name t4zh7bev. Value is the FSx MGS *IP* (not DNS): this is the exact NID validated on staging
# and it works both same-VPC and cross-VPC (the private DNS name fails to resolve over peering ->
# "mount.lustre: Can't parse NID"). Re-check if the FSx is ever recreated:
#   aws fsx describe-file-systems --file-system-ids fs-09f8ba285ecf05b0e --query 'FileSystems[0].NetworkInterfaceIds'
# The lab-worker can override per apply via terraform.tfvars (LAB_FSX_LUSTRE_DNS env). Set to "" only
# to deliberately roll back to the legacy EFS path (lab_efs_nfs_host).
variable "lab_fsx_lustre_dns" {
  type        = string
  default     = "10.50.10.147"
  description = "FSx Lustre MGS NID IP (<ip>@tcp:/<mount>) — staging-tested prod FSx. Empty skips Lustre and falls back to lab_efs_nfs_host."
}

variable "lab_fsx_lustre_mount_name" {
  type        = string
  default     = "t4zh7bev"
  description = "FSx Lustre mount name from console (prod slabs fsx). Used as @tcp:/<name>."
}

# After root mount on /efs, user-data mkdirs /efs/tools/<code> on the same filesystem (PD / DV / AL). Not separate NFS mounts.
variable "lab_efs_tools_mount_codes" {
  type        = list(string)
  default     = []
  description = "Per IT runbook: after nfs root on /efs, user-data bind-mounts /efs/tools/<code> → /<code> for each code (PD/DV/AL). Set per learner domain at apply time (e.g. [\"PD\"] only). Empty [] = root /efs only, no /PD /DV /AL binds."
  validation {
    condition     = length(var.lab_efs_tools_mount_codes) == 0 || alltrue([for c in var.lab_efs_tools_mount_codes : contains(["PD", "DV", "AL"], c)])
    error_message = "lab_efs_tools_mount_codes must be empty or contain only PD, DV, or AL."
  }
}

# When VPC DNS cannot resolve the EFS DNS name, user-data calls `aws efs describe-mount-targets`
# and mounts the mount-target IPv4 for this instance's subnet (bypasses resolver).
variable "lab_efs_aws_ip_fallback" {
  type        = bool
  default     = true
  description = "If true and DNS mount fails, resolve mount-target IP via AWS API and mount nfs4 by IP. Instance role needs elasticfilesystem:DescribeMountTargets."
}

# Optional static mount-target IPv4 (e.g. 10.10.3.41). Used when VPC DNS and DescribeMountTargets both fail.
# Set via Terraform tfvars or backend env LAB_EFS_MOUNT_TARGET_IP at apply time.
variable "lab_efs_mount_target_ip" {
  type        = string
  default     = "10.10.3.41"
  description = "EFS mount-target IPv4 for fstab + nfs4 mount when VPC DNS/API fallback fail. Override per env or set LAB_EFS_MOUNT_TARGET_IP in backend. Empty skips static IP path."
}

# Base64(JSON) from the app at apply time: { session_user, source_files[], ad_groups_any[] }.
# User-data decodes after AD join + SSSD, optionally verifies id -Gn against ad_groups_any (OR),
# then writes /etc/profile.d to `source` each existing path (e.g. /efs/tools/PD). Empty = skip.
variable "lab_efs_tool_profile_b64" {
  type        = string
  default     = ""
  description = "Base64(JSON): { session_user, source_files[], ad_groups_any[] }. Applied after LabBootstrap=READY (background); does not wait for session_user during user-data (backend creates AD account on StartLab)."
}

variable "lab_efs_open_tool_execute" {
  type        = bool
  default     = true
  description = "After EFS mount, chmod a+rX on vendor bin/linux64 trees so AD learners (high NFS UIDs) can execute ICC2/genus/etc. Runs in background during user-data so LabBootstrap/AD join are not blocked on multi-TB NFS trees."
}

#resource "aws_iam_instance_profile" "ssm_profile" {
#  name = "ssm-profile"
#  role = "AmazonSSMManagedInstanceCore"
#}

# resource "aws_iam_role" "ssm_role" {
#   name = "LabSSMRole"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ssm_attach" {
#   role       = aws_iam_role.ssm_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }

# resource "aws_iam_instance_profile" "ssm_profile" {
#   name = "LabSSMProfile"
#   role = aws_iam_role.ssm_role.name
# }

