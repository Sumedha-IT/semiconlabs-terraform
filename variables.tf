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
  description = "Lab AMI — ap-south-1 golden image (GNOME+DCV+PAM pre-baked; AD join + SSSD finalize in user-data / SSM)"
  type        = string
  default     = "ami-066401294ec783ea4"
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
  description = "Subnet ID where lab EC2 is launched (staging private subnet default)"
  type        = string
  default     = "subnet-0c4d6990bb08a09b2"
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

variable "aws_region" {
  description = "Region for aws CLI in user-data (tags, SSM). Matches Semiconlabs-backend .env AWS_REGION."
  type        = string
  default     = "ap-south-1"
}

# AWS Managed Microsoft AD directory id (same as AD_DIRECTORY_ID in Semiconlabs-backend .env).
variable "ad_directory_id" {
  description = "Directory Service id (d-xxxxxxxxxx). Required when enable_ad_join=true and ad_join_mechanism=ssm_aws_managed."
  type        = string
  default     = "d-9f67755145"
}

variable "ad_join_mechanism" {
  description = <<-EOT
    ssm_aws_managed — recommended for AWS Managed Microsoft AD: Terraform creates aws_ssm_association with document AWS-JoinDirectoryServiceDomain (no join password on the instance).
    realm_userdata — use realm join in user-data; requires ad_join_user + SSM parameter for that account's password.
  EOT
  type        = string
  default     = "ssm_aws_managed"

  validation {
    condition     = contains(["ssm_aws_managed", "realm_userdata"], var.ad_join_mechanism)
    error_message = "ad_join_mechanism must be ssm_aws_managed or realm_userdata."
  }
}

# Per-instance AD join (do not bake join into golden AMI).
variable "enable_ad_join" {
  description = "If true, join this instance to the directory (SSM document for Managed AD, or realm join in user-data)."
  type        = bool
  default     = true

  validation {
    condition = !var.enable_ad_join || (
      (var.ad_join_mechanism == "realm_userdata" &&
        var.ad_domain != "" &&
        var.ad_join_user != "" &&
        (var.ad_join_password_secretsmanager_secret_id != "" ||
          var.ad_join_password_ssm_parameter_name != "")) ||
      (var.ad_join_mechanism == "ssm_aws_managed" &&
        var.ad_directory_id != "" &&
        var.ad_domain != "" &&
        length(var.ad_dns_ips) > 0)
    )
    error_message = "When enable_ad_join=true: ssm_aws_managed needs ad_directory_id, ad_domain, ad_dns_ips (no join password in Terraform). realm_userdata needs ad_join_user plus either ad_join_password_secretsmanager_secret_id or ad_join_password_ssm_parameter_name."
  }
}

variable "ad_domain" {
  description = "AD DNS domain / Kerberos realm name. Matches AD_DOMAIN in Semiconlabs-backend .env (sumedhalabs.com)."
  type        = string
  default     = "sumedhalabs.com"
}

variable "ad_join_user" {
  description = "Only for ad_join_mechanism=realm_userdata: dedicated join UPN (e.g. svc-lab-join@sumedhalabs.com). Ignored for ssm_aws_managed."
  type        = string
  default     = ""
}

variable "ad_join_password_ssm_parameter_name" {
  description = "Only for realm_userdata: SSM SecureString name holding the join account password. Ignored if ad_join_password_secretsmanager_secret_id is set (Secrets Manager is used first) or for ssm_aws_managed."
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
  default     = ["10.10.149.108", "10.10.136.0"]
}

variable "dcv_use_console_sessions" {
  description = "If true, DCV automatic console + create-session (matches dedicated console-only backend). If false, virtual-session style dcv.conf."
  type        = bool
  default     = true
}

variable "dcv_web_listen_all" {
  description = "If true, add web-listen-endpoints 0.0.0.0:8443 + disable QUIC in /etc/dcv/dcv.conf (browser access)."
  type        = bool
  default     = true
}

variable "ad_ssm_join_wait_max_sec" {
  description = "When ad_join_mechanism=ssm_aws_managed, poll up to this many seconds for join (SSM Automation runs after boot)."
  type        = number
  default     = 900
}

variable "ad_sssd_default_shell" {
  description = "Inserted into sssd.conf under [domain/<dns>] after join if default_shell is absent (DCV/SSH login shell)."
  type        = string
  default     = "/bin/bash"
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

