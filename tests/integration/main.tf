terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Environment = "test"
      Project     = "Module-Test"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. VPC 모듈 테스트
# ------------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  region   = "ap-northeast-2"
  name     = "test-vpc"
  vpc_cidr = "10.0.0.0/16"

  public_subnet_a_cidr = "10.0.1.0/24"
  public_subnet_c_cidr = "10.0.2.0/24"

  was_subnet_a_cidr = "10.0.10.0/24"
  was_subnet_c_cidr = "10.0.11.0/24"

  db_subnet_a_cidr = "10.0.20.0/24"
  db_subnet_c_cidr = "10.0.21.0/24"
}

# ------------------------------------------------------------------------------
# 2. WAS 모듈 테스트
# ------------------------------------------------------------------------------
module "was" {
  source = "../../modules/was-app"

  name = "test-was-app"

  vpc_id = module.vpc.vpc_id

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.was_subnet_ids

  ami_id        = "ami-00a51cc7a8cd53e3f"
  instance_type = "t2.micro"
  key_name      = "test-key"

  asg_desired = 2
  asg_max     = 4
  asg_min     = 2
}

# ------------------------------------------------------------------------------
# 3. RDS 모듈 테스트
# ------------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  name = "test-rds"

  vpc_id        = module.vpc.vpc_id
  db_subnet_ids = module.vpc.db_subnet_ids

  was_sg_id = module.was.was_sg_id

  db_engine            = "mysql"
  db_engine_version    = "8.0"
  db_instance_class    = "db.t3.micro"
  db_allocated_storage = 20

  db_multi_az = false

  db_name     = "testdb"
  db_username = "admin"

  db_password = "TestPassword123!"
}