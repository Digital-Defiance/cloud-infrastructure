# rds
data "aws_rds_orderable_db_instance" "selected" {
  engine                     = "postgres"
  engine_version             = "15.4"
  license_model              = "postgresql-license"
  preferred_instance_classes = ["db.t3.micro"]
}

module "postgresql_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/postgresql"
  version = "~> 5.0"
  name    = "postgresql_security_group"
  vpc_id  = module.vpc.vpc_id

  egress_ipv6_cidr_blocks = concat(module.vpc.private_subnets_ipv6_cidr_blocks, module.vpc.public_subnets_ipv6_cidr_blocks)
  egress_cidr_blocks      = concat(module.vpc.private_subnets_cidr_blocks, module.vpc.public_subnets_cidr_blocks)
  ingress_cidr_blocks     = concat(module.vpc.private_subnets_cidr_blocks, module.vpc.public_subnets_cidr_blocks)
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  apply_immediately  = true
  create_db_instance = true

  db_subnet_group_name = module.vpc.database_subnet_group_name
  subnet_ids           = module.vpc.database_subnets
  vpc_security_group_ids = [
    module.vpc.default_security_group_id,
    module.postgresql_security_group.security_group_id
  ]

  identifier = "cloud-infra-db-3"

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

output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_port" {
  value = module.db.db_instance_port
}

output "db_instance_username" {
  value = module.db.db_instance_username
}
