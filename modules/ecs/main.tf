# 0. CloudWatch Log Group 
# 1. Security Groups 
# 2. ACM & Route53 (도메인 인증)
# 3. ALB & Target Group
# 4. IAM Roles (ECS Node & Task Roles & ssm)
# 5. ECS Cluster & Compute (Cluster, LT, ASG, CP)
# 6. ECS Task & Service

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# CloudFront의 IP 대역
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# (참고) account_id를 가져오기 위해 data source가 없다면 추가 필요
data "aws_caller_identity" "current" {}
# ==============================================================================
# 0. CloudWatch Log Group 
# ==============================================================================
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "${var.name}/ecs/" 
  retention_in_days = 7
}


# ==============================================================================
# 1. Security Groups 
# ==============================================================================

# 1) ALB용 보안 그룹 (외부 80/443 허용)
resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Security group for public ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb-sg" }
}

# 2) ECS 노드(EC2)용 보안 그룹 (ALB 트래픽 허용)
resource "aws_security_group" "ecs_node_sg" {
  name        = "${var.name}-ecs-node-sg"
  description = "Security group for ECS Nodes"
  vpc_id      = var.vpc_id

  # 동적 포트 매핑을 위해 ALB에서 오는 모든 포트(0-65535) 허용
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description     = "Allow All Traffic from ALB for Dynamic Port Mapping"
  }

  # SSH 접속 
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Allow SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-ecs-node-sg" }
}

# ==============================================================================
# 2. ACM & Route53 (도메인 인증)
# ==============================================================================

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = { Name = "${var.name}-acm-cert" }

  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ==============================================================================
# 3. ALB & Target Group
# ==============================================================================

resource "aws_lb" "main" {
  name               = "${var.name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.name}-lb" }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${var.name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance" # ECS EC2(Bridge) 모드는 instance 타입 필수

  health_check {
    path                = "/" # 혹은 /actuator/health
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = { Name = "${var.name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ==============================================================================
# 4. IAM Roles (ECS Node & Task Roles & ssm & SSM Parameter Store)
# ==============================================================================

# 4-1. EC2 Instance Role (ECS Agent)
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.name}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# ECS 에이전트용 필수 정책 연결
resource "aws_iam_role_policy_attachment" "ecs_instance_role_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}



# EC2용 인스턴스 프로파일
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# 4-2. ECS Task Execution Role (이미지 Pull, 로그 저장)
resource "aws_iam_role" "ecs_exec_role" {
  name = "${var.name}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_exec_role_attach" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 4-3. ECS Task Role (앱이 S3 접근할 권한)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# S3 접근 정책
resource "aws_iam_policy" "s3_access_policy" {
  name        = "${var.name}-s3-policy"
  description = "Allow ECS Task to access S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_task_s3_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

######### Session Manage (SSM) ################
# 접속 허용 정책 연결
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ecs_exec_ssm" {
  name        = "${var.name}-ecs-exec-ssm-policy"
  description = "Allow ECS Exec to container"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# 위 정책을 Task Role에 연결
resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_ssm.arn
}

########### SSM Parameter Store ##############
resource "aws_iam_policy" "ecs_ssm_read" {
  name        = "${var.name}-ecs-ssm-read-policy"
  description = "Allow ECS Task Execution Role to read SSM Parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "kms:Decrypt" # SecureString 복호화에 필요
        ]
        # 특정 경로의 파라미터만 읽도록 제한 (보안 권장)
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.name}/*"
      }
    ]
  })
}

# 2. 정책을 ecs_exec_role에 연결 (기존 exec role에 연결해야 함)
resource "aws_iam_role_policy_attachment" "ecs_exec_ssm_read_attach" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = aws_iam_policy.ecs_ssm_read.arn
}

# ==============================================================================
# 5. ECS Cluster & Compute (Cluster, LT, ASG, CP)
# ==============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.name}-cluster"
}

resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "${var.name}-ecs-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type 
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs_node_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.name}-ecs-node" }
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "${var.name}-ecs-asg"
  vpc_zone_identifier = var.private_subnet_ids
  max_size            = var.asg_max
  min_size            = var.asg_min
  desired_capacity    = var.asg_desired

  protect_from_scale_in = true # Capacity Provider 사용 시 필수

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "main" {
  name = "${var.name}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100 # 서버 가동률 목표치
    }
    managed_termination_protection = "ENABLED" # 서버(ASG) - 컨테이너(CP) 팀킬 방지
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.main.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.main.name
  }
}

# ==============================================================================
# 6. ECS Task & Service
# ==============================================================================

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name}-task"
  network_mode             = "bridge" # EC2 모드 전용
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn # ECS Agent - 부팅
  task_role_arn            = aws_iam_role.ecs_task_role.arn # S3 - upload

  container_definitions = jsonencode([
    {
      name      = "${var.name}-container"
      image     = "${var.ecr_repository_url}:latest"
      essential = true

      environment = var.container_env
      secrets = var.container_secrets
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0    # 랜덤 포트 (Dynamic Port Mapping)
          protocol      = "tcp"
        }
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "${var.name}/ecs/"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "main" {
  name            = "${var.name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"
  enable_execute_command = true # 컨테이너 내부 접속(exec) 기능 활성화 (ssm)
  # 로드밸런서 연결
  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "${var.name}-container"
    container_port   = var.container_port
  }

  # 순서 보장 (Listener가 없으면 배포 실패함)
  depends_on = [aws_lb_listener.https]
}