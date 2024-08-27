
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

output "subnet_ids" {
  value = data.aws_subnets.selected
}

