# 1. DB Subnet Group
# 2. Security Group for RDS
# 3. RDS Instance

terraform {
  required_version = ">= 1.0.0"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. DB Subnet Group
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids
  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

# ------------------------------------------------------------------------------
# 2. Security Group for RDS
# ------------------------------------------------------------------------------
resource "aws_security_group" "db_sg" {
  name        = "${var.name}-db-sg"
  description = "Security group for RDS DB"
  vpc_id      = var.vpc_id

  # 인바운드 규칙: WAS SG에서 오는 MySQL(3306) 트래픽만 허용
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.was_sg_id] # WAS SG ID 참조
    description     = "Allow MySQL from WAS SG"
  }

  # 아웃바운드 규칙 (기본값: 모두 허용)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-db-sg"
  }
}

# ------------------------------------------------------------------------------
# 3. RDS Instance
# ------------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier        = "${var.name}-db-instance"
  allocated_storage = var.db_allocated_storage
  engine            = var.db_engine
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  multi_az          = var.db_multi_az


  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  skip_final_snapshot = true

  tags = {
    Name = "${var.name}-db"
  }
}

# ------------------------------------------------------------------------------
# 4. SSM Parameter Store (Secrets & Config)
# ------------------------------------------------------------------------------

# 1) DB 비밀번호 저장 (암호화)
resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.name}/db/password"
  description = "Password for the RDS instance"
  type        = "SecureString"  # KMS로 자동 암호화
  value       = var.db_password
  
  tags = {
    Name = "${var.name}-db-password"
  }
}

# 2) DB 접속 주소 저장 (암호화 안 함)
resource "aws_ssm_parameter" "db_endpoint" {
  name        = "/${var.name}/db/endpoint"
  type        = "String"       
  value       = aws_db_instance.main.address # RDS 리소스에서 주소 추출
  
  tags = {
    Name = "${var.name}-db-endpoint"
  }
}

resource "aws_ssm_parameter" "db_name" {
  name        = "/${var.name}/db/name"
  description = "Database name"
  type        = "String"
  value       = var.db_name
}