# ec2

# ---------- INPUT --------------------- 
variable "public_ssh_key" {
  type = string
}

variable "my_ip_address" {
  type = string
}

# ---------- DATA -------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# ------------- RESOURCES -----------------------

resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

resource "aws_key_pair" "default" {
  key_name   = "eks-tmp-manager-instance-key"
  public_key = var.public_ssh_key
}


module "https_443_security_group" {
  source              = "terraform-aws-modules/security-group/aws//modules/https-443"
  name                = "https_security_group"
  version             = "~> 5.0"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
}

module "ssh_security_group" {
  name                = "ssh-security-group"
  source              = "terraform-aws-modules/security-group/aws//modules/ssh"
  version             = "~> 5.0"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = [var.my_ip_address]
}

module "ec2_temp_instance_v2" {
  create = true

  ami       = data.aws_ami.ubuntu.id
  source    = "terraform-aws-modules/ec2-instance/aws"
  user_data = file("${path.module}/user_data.sh")

  name = "eks-cluster-tmp-manager-instance-v2"


  instance_type = "t3.micro"

  key_name               = resource.aws_key_pair.default.key_name
  monitoring             = true
  vpc_security_group_ids = [module.ssh_security_group.security_group_id]
  subnet_id              = module.vpc.public_subnets[0]

  root_block_device = [
    {
      volume_size = 30
    }
  ]

  instance_tags = {
    GitHubRepo = "https://github.com/Digital-Defiance/cloud-infrastructure"
    Name       = "eks-cluster-tmp-manager-instance-v2"
  }

  tags = {
    GitHubRepo  = "https://github.com/Digital-Defiance/cloud-infrastructure"
    Terraform   = "true"
    Environment = "production"
  }

  metadata_options = {
    http_tokens = "required"
  }

}

resource "aws_eip" "ip_of_manager_instance" {
  domain = "vpc"
  tags = {
    Name       = "ip_of_manager_instance"
    GitHubRepo = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }
}

resource "aws_eip_association" "eip_assoc" {
  count         = 1
  instance_id   = module.ec2_temp_instance_v2.id
  allocation_id = resource.aws_eip.ip_of_manager_instance.id
  depends_on = [
    module.vpc,
  ]
}


# ----------------- OUTPUT --------------------

output "user_data" {
  value = file("${path.module}/user_data.sh")

}

output "ssh_command" {
  value = try("ssh -i id_ed ubuntu@${aws_eip.ip_of_manager_instance.public_ip}", null)
}

