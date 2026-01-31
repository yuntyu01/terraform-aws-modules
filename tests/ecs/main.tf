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

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}


# ------------------------------------------------------------------------------
# 1. Global & Base Resources
# ------------------------------------------------------------------------------
locals {
  assets_bucket_name = "dailoapp-test-static-assets-2025"
  db_name            = "testdb"
  db_username        = "admin"
  db_password        = "TestPassword123!"
}

data "aws_route53_zone" "selected" {
  name = "dailoapp.com"
}

module "ecr" {
  source = "../../global/ecr"
  name   = "test-server"
}

# ------------------------------------------------------------------------------
# 2. VPC 모듈 테스트
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
# 2. ECS App 모듈 테스트 
# ------------------------------------------------------------------------------
module "ecs" {
  source = "../../modules/ecs"

  name   = "test-ecs-app"
  region = "ap-northeast-2" # CloudWatch 로그 등을 위해 사용

  ami_id = "ami-0291c43558f414816"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.was_subnet_ids # ECS 노드가 배치될 Private Subnet

  bucket_name        = local.assets_bucket_name  # IAM 정책 연결용
  ecr_repository_url = module.ecr.repository_url # 이미지 Pull용

  # [EC2 설정]
  key_name      = "test-key" # AWS 콘솔에 등록된 키페어 
  instance_type = "t3.medium"

  # [Auto Scaling 설정]
  asg_min     = 1
  asg_max     = 2
  asg_desired = 1

  cpu    = 512
  memory = 1024

  desired_count = 2
  container_env = [
    {
      name  = "SPRING_DATASOURCE_URL"
      value = "jdbc:mysql://${module.rds.address}:3306/${local.db_name}?useSSL=false&allowPublicKeyRetrieval=true&characterEncoding=UTF-8&serverTimezone=Asia/Seoul"
    },
    {
      name  = "SPRING_DATASOURCE_USERNAME"
      value = local.db_username
    },
    {
      name  = "TZ"
      value = "Asia/Seoul"
    },
    {
      name  = "AWS_REGION"
      value = "ap-northeast-2"
    },
    {
      name  = "AWS_S3_BUCKET"
      value = local.assets_bucket_name
    }
  ]

  container_secrets = [
    {
      name      = "SPRING_DATASOURCE_PASSWORD"
      valueFrom = module.rds.ssm_db_password_arn
    }
  ]
}

# ------------------------------------------------------------------------------
# 3. RDS 모듈 테스트
# ------------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  name = "test-rds"

  vpc_id        = module.vpc.vpc_id
  db_subnet_ids = module.vpc.db_subnet_ids

  # ECS 노드(EC2)들이 DB에 접속할 수 있도록 SG 허용
  was_sg_id = module.ecs.ecs_node_security_group_id

  db_engine            = "mysql"
  db_engine_version    = "8.0"
  db_instance_class    = "db.t3.micro"
  db_allocated_storage = 20

  db_multi_az = false

  db_name     = local.db_name
  db_username = local.db_username
  db_password = local.db_password
}

# ------------------------------------------------------------------------------
# 4. CDN 모듈 테스트
# ------------------------------------------------------------------------------
module "cdn" {
  source = "../../modules/cdn"

  providers = {
    aws.virginia = aws.virginia
  }

  name = "test-cdn"

  bucket_name = local.assets_bucket_name

  domain_name     = "dailoapp.com"
  route53_zone_id = data.aws_route53_zone.selected.zone_id

  # ECS의 ALB 주소 연결 (동적 콘텐츠 가속용)
  alb_dns_name = module.ecs.alb_dns_name
}