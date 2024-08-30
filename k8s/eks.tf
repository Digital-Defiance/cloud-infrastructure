terraform {
  cloud {
    organization = "digitaldefiance"
    ## Required for Terraform Enterprise; Defaults to app.terraform.io for HCP Terraform
    hostname = "app.terraform.io"
    workspaces {
      name = "cloud-infrastructure"
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
  version = "5.13.0"

  name = "vpc-cloud-dev-infra"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets   = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  database_subnets = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]

  database_subnet_group_name = "rds_subnet_group"

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_flow_log       = true
  flow_log_traffic_type = "REJECT"

  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  tags = {
    Name       = "cloud-dev-infra-vpc"
    GitHubRepo = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    GitHubRepo               = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    GitHubRepo                        = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }
}

# data "aws_rds_engine_version" "test" {_
#   preferred_versions = ["15.4"]
#   engine = "postgres"
# }

data "aws_rds_orderable_db_instance" "selected" {
  engine                     = "postgres"
  engine_version             = "15.4"
  license_model              = "postgresql-license"
  preferred_instance_classes = ["db.t3.micro"]
}

output "vpc" {
  value = module.vpc
}
module "db" {
  source = "terraform-aws-modules/rds/aws"

  create_db_instance = true

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  subnet_ids             = module.vpc.database_subnets

  identifier = "cloud-infra-db-2"

  major_engine_version = "15"
  engine               = "postgres"
  engine_version       = "15.4"
  family               = "postgres15"

  instance_class    = "db.t3.micro"
  allocated_storage = 10

  username = "postgresqlcloudinfra"

  manage_master_user_password = true

  tags = {
    Environment = "production"
    Terraform   = "true"
    GitHubRepo  = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

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


  cluster_additional_security_group_ids = [
    module.https_443_security_group.security_group_id
  ]

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
  version = "5.44.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
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
    Name       = "ip_of_manager_instance"
    GitHubRepo = "https://github.com/Digital-Defiance/cloud-infrastructure"
  }
  domain = "vpc"
}

resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
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


resource "aws_eip_association" "eip_assoc" {
  count         = 1
  instance_id   = module.ec2_temp_instance_v2.id
  allocation_id = resource.aws_eip.ip_of_manager_instance.id
  depends_on = [
    module.vpc,
  ]
}

output "user_data" {
  value = file("${path.module}/user_data.sh")

}

output "db_module" {
  value = module.db
}

output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_port" {
  value = module.db.db_instance_port
}

output "ssh_command" {
  value = try("ssh -i id_ed ubuntu@${aws_eip.ip_of_manager_instance.public_ip}", null)
}

output "aws_configuration_command" {
  value = "aws eks update-kubeconfig --region eu-south-1 --name ${module.eks.cluster_name}"
}

output "rds_info" {
  value = data.aws_rds_orderable_db_instance.selected

}
