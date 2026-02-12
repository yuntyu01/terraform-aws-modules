terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. IAM Role (기존 유지)
# ------------------------------------------------------------------------------
# 그라파나 전용 Task Role 
resource "aws_iam_role" "grafana_task_role" {
  name = "${var.name}-grafana-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
        {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cw_read" {
  role       = aws_iam_role.grafana_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_ec2_read" {
  role       = aws_iam_role.grafana_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}
# ------------------------------------------------------------------------------
# 2. ALB Listener Rule & Target Group
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "grafana_tg" {
  name        = "${var.name}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance" 

  health_check {
    path                = "/api/health" 
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = var.http_listener_arn
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_tg.arn
  }

  condition {
    host_header {
      values = ["grafana.${var.domain_name}"] 
      }
  }
}

# ------------------------------------------------------------------------------
# 3. ECS Service & Task Definition
# ------------------------------------------------------------------------------

locals {
  # Init Container가 실행할 명령어
  # 1. mysql-client 설치
  # 2. admin(root) 계정으로 접속 (var.db_password 사용)
  # 3. grafana DB 생성 (이미 있으면 통과)
  init_command = [
    "/bin/sh",
    "-c",
    "apk add --no-cache mysql-client && mysql -h ${var.rds_endpoint} -u admin -p'${var.db_password}' -e \"CREATE DATABASE IF NOT EXISTS grafana;\""
  ]
}

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.name}-grafana"
  network_mode             = "bridge" 
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  task_role_arn            = aws_iam_role.grafana_task_role.arn
  execution_role_arn       = var.ecs_exec_role_arn

  container_definitions = jsonencode([  
    # ===========================================================
    # [컨테이너 1] Init Container: DB 생성용
    # ===========================================================
    {
      name      = "db-init"
      image     = "alpine:3.18"  
      essential = false          
      command   = local.init_command
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.app_log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "db-init"
        }
      }
    }, 

    # ===========================================================
    # [컨테이너 2] Grafana Container: 실제 서비스
    # ===========================================================
    { 
      name      = "grafana"
      image     = "grafana/grafana:latest"
      essential = true
      
      # Init 컨테이너가 성공해야만 시작
      dependsOn = [
        {
          containerName = "db-init"
          condition     = "SUCCESS"
        }
      ]

      # Bridge 모드에서 hostPort = 0 은 랜덤 포트 할당 
      portMappings = [{ containerPort = 3000, hostPort = 0, protocol = "tcp" }]
      
      environment = concat([
        # 1. 기본 프로토콜 및 보안
        { name = "GF_SERVER_PROTOCOL", value = "http" },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = var.grafana_admin_password },

        # 2. DB 연결 - 데이터 영구 저장용
        # HOST, NAME, USER, PASSWORD는 root main.tf에서 주입받음
         # 3. 세션 공유 (HA 구성 필수)
        { name = "GF_SESSION_PROVIDER", value = "database" },
        { name = "GF_SESSION_PROVIDER_CONFIG", value = "sessions" },
        { name = "GF_SESSION_COOKIE_SECURE", value = "true" },
        ], 
        var.grafana_container_env) # 외부에서 주입받는 변수와 합침

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.app_log_group_name 
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.name}-grafana-service"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 2      
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana_tg.arn
    container_name   = "grafana"
    container_port   = 3000
  }
  depends_on = [aws_lb_listener_rule.grafana]
}