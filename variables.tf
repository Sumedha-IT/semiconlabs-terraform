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
  description = "Lab AMI — ap-south-1 golden image (semiconlabs-dcv-watch baked via golden-ami-dcv-watcher.sh)"
  type        = string
  default     = "ami-035d56902b1949f48"
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

