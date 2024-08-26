terraform {
  backend "s3" {
    key    = "cloud-infrastructure"
    bucket = "digitaldefiance-terraform-backend"
    region = "eu-south-1"
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

# Filter out local zones, which are not currently supported 
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "cloud-dev-infra"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log       = true
  flow_log_traffic_type = "REJECT"

  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60


  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = "cloud-dev-infra"
  cluster_version = "1.29"

  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  # https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group
  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.small"]
      capacity_type  = "SPOT"

      min_size     = 0
      max_size     = 3
      desired_size = 1
    }
  }
}



# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}


output "aws_configuration_command" {
  value = "aws eks update-kubeconfig --region eu-south-1 --name ${module.eks.cluster_name}"
}




variable "public_ssh_key" {
  type = string
}

resource "aws_key_pair" "default" {
  key_name   = "eks-tmp-manager-instance-key"
  public_key = var.public_ssh_key
}

variable "my_ip_address" {
  type = string
}

module "ssh_security_group" {
  name                = "ssh-security-group"
  source              = "terraform-aws-modules/security-group/aws//modules/ssh"
  version             = "~> 5.0"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = [var.my_ip_address]
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

resource "aws_eip" "ip_of_manager_instance" {
  tags = {
    Name = "ip_of_manager_instance"
  }
  domain = "vpc"
}

resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

module "ec2_instance" {
  ami       = data.aws_ami.ubuntu.id
  source    = "terraform-aws-modules/ec2-instance/aws"
  user_data = <<EOF
#!/bin/bash

# INSTALL DOCKER
sudo apt update -y
sudo apt -y install docker.io
sudo service docker start
sudo usermod -a -G docker ec2-user
sudo chmod 666 /var/run/docker.sock
docker version

# INSTALL NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

# INSTALL NODE 20.16.0
nvm install 20.16.0
nvm use 20.16.0

# INSTALL DEVCONTAINERS CLI 0.65.0
npm install -g @devcontainers/cli@0.65.0

# INSTALL MAKE AND SETUP DEV CONTAINER
sudo apt install make
cd $HOME
git clone https://github.com/Digital-Defiance/cloud-infrastructure.git
cd cloud-infrastructure
make build
EOF

  name   = "eks-cluster-tmp-manager-instance"
  create = true

  instance_type = "t3.micro"

  key_name               = resource.aws_key_pair.default.key_name
  monitoring             = true
  vpc_security_group_ids = [module.ssh_security_group.security_group_id]
  subnet_id              = module.vpc.public_subnets[0]

  instance_tags = {
    Name = "eks-cluster-tmp-manager-instance"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

  metadata_options = {
    http_tokens = "required"
  }

}


resource "aws_eip_association" "eip_assoc" {
  count         = 1
  instance_id   = module.ec2_instance.id
  allocation_id = resource.aws_eip.ip_of_manager_instance.id
  depends_on = [
    module.vpc,
  ]
}
