
terraform {
  cloud {
    organization = "digitaldefiance"
    ## Required for Terraform Enterprise; Defaults to app.terraform.io for HCP Terraform
    hostname = "app.terraform.io"
    workspaces {
      name = "cloud-infrastructure-cicd"
    }
  }


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.5"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3.4"
    }
  }

  required_version = "~> 1.3"
}

provider "aws" {
  region = "eu-south-1"
}

resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}


data "aws_subnets" "selected" {
  tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

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

data "aws_security_group" "selected" {
  tags = {
    Name = "https_security_group"
  }
}


data "aws_db_instance" "selected" {
  tags = {
    GitHubRepo = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }
}

variable "secret_arn" {
  type = string
}

data "aws_secretsmanager_secret" "secrets" {
  arn = var.secret_arn
}

data "aws_secretsmanager_secret_version" "current" {
  secret_id = data.aws_secretsmanager_secret.secrets.id
}

output "db_instance_password" {
  value     = jsondecode(data.aws_secretsmanager_secret_version.current.secret_string)["password"]
  sensitive = true
}

output "db_instance_master_username" {
  value = data.aws_db_instance.selected.master_username
}

output "db_instance_endpoint" {
  value = data.aws_db_instance.selected.endpoint
}

output "security_group_id" {
  value = data.aws_security_group.selected.id
}

output "ami" {
  value = data.aws_ami.ubuntu.id
}

output "subnet_ids" {
  value = data.aws_subnets.selected
}

