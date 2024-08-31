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

