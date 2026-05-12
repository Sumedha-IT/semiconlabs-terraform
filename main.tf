provider "aws" {
  region = "ap-south-1"
}

locals {
  lower_ad_domain = lower(var.ad_domain)
  # aws_ssm_association.parameters only accepts string values (not lists). AWS also rejects a single
  # comma-separated value for dnsIpAddresses (validates the whole string as one IPv4).
  # Passing one directory DNS IP satisfies SSM; user-data still applies the full var.ad_dns_ips list
  # to the NIC resolver (nmcli). Put the primary DC DNS first in ad_dns_ips.
  ad_ssm_join_dns_ip = trimspace(var.ad_dns_ips[0])
}

# Importing the SG
data "aws_security_group" "TerraformSecurityGroup" {
  id = "sg-04430765f75fb1634"
}

# Generate an SSH key pair
resource "tls_private_key" "master_key_gen" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create AWS key pair from generated TLS key
resource "aws_key_pair" "master_key_pair" {
  key_name   = "${var.name}-${var.instance_name}-${var.suffix}"
  public_key = tls_private_key.master_key_gen.public_key_openssh
}

# Output the private key content
output "private_key_pem" {
  value     = tls_private_key.master_key_gen.private_key_pem
  sensitive = true
}

# Lab instance (Amazon Linux / DCV); bootstrap enables SSH, EFS, DCV, SSSD
resource "aws_instance" "CentOS8-AMD" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.master_key_pair.key_name
  subnet_id              = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids = [data.aws_security_group.TerraformSecurityGroup.id]
  iam_instance_profile   = "LabSSMRole"

  root_block_device {
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = var.delete_root_volume_on_termination
  }


  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    aws_region                            = var.aws_region
    suffix                                = var.suffix
    enable_ad_join                        = var.enable_ad_join
    ad_join_mechanism                     = var.ad_join_mechanism
    ad_domain                             = var.ad_domain
    lower_ad_domain                       = local.lower_ad_domain
    ad_join_user                            = var.ad_join_user
    ad_join_password_ssm_parameter_name   = var.ad_join_password_ssm_parameter_name
    ad_join_password_secretsmanager_secret_id = var.ad_join_password_secretsmanager_secret_id
    ad_computer_ou                          = var.ad_computer_ou
    ad_dns_ips                            = var.ad_dns_ips
    dcv_use_console_sessions              = var.dcv_use_console_sessions
    dcv_web_listen_all                    = var.dcv_web_listen_all
    ad_ssm_join_wait_max_sec              = var.ad_ssm_join_wait_max_sec
    ad_sssd_default_shell                 = var.ad_sssd_default_shell
  })
  tags = {
    Name         = "${var.name}-${var.instance_name}-${var.suffix}"
    map-migrated = "DADS45OSDL"
    LabBootstrap = "READY"
  }
}

# AWS Managed Microsoft AD: official SSM Automation (no realm join password on the instance).
resource "aws_ssm_association" "managed_ad_domain_join" {
  count = var.enable_ad_join && var.ad_join_mechanism == "ssm_aws_managed" ? 1 : 0

  name             = "AWS-JoinDirectoryServiceDomain"
  association_name = substr("${var.name}-${var.instance_name}-${var.suffix}-ad-join", 0, 128)

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
  filename        = "${var.name}-${var.instance_name}-${var.suffix}.pem"
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

# Output the PEM file for SSH (now using generated keypair name)
output "pem_file_for_ssh" {
  value     = aws_key_pair.master_key_pair.key_name
  sensitive = true
}

output "instance_id" {
  value = aws_instance.CentOS8-AMD.id
}

