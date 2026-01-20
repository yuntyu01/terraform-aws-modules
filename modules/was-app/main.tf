# 1. Security Group - 2개 ([Pub]Alb 1개, [Pri]was 1개)
# 2. ACM & Route53 Validation 
# 3. ALB & Listener & Target Group - 1개 (Listener - http, TG - was.sg)
# 4. IAM Role (WAS(EC2)를 위한 S3 접근 권한)
# 5. Launch Template 
# 6. Auto Scaling Group 

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Security Group 
# ------------------------------------------------------------------------------

# Public ALB용 보안 그룹
resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Security group for public ALB"
  vpc_id      = var.vpc_id

  # 인바운드 규칙: 외부 HTTP/HTTPS 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS"
  }

  # 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all"
  }

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

# [Private] WAS(EC2)용 보안 그룹
resource "aws_security_group" "was_sg" {
  name        = "${var.name}-was-sg"
  description = "Security group for WAS servers"
  vpc_id      = var.vpc_id

  # 인바운드 규칙: ALB에서 오는 HTTP 허용, 테스트용 SSH 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description = "Allow HTTP only from ALB"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH"
  }



  # 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all"
  }

  tags = {
    Name = "${var.name}-was-sg"
  }
}

# ------------------------------------------------------------------------------
# 2. ACM & Route53 Validation 
# ------------------------------------------------------------------------------

# 1) 인증서 발급 요청
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name      
  validation_method = "DNS"

  tags = {
    Name = "${var.name}-acm-cert"
  }

  lifecycle {
    # 새거 만들고 지우기 (서비스 연결 끊김 방지)
    create_before_destroy = true
  }
}

# 2) DNS 검증 레코드 생성 (Route53에 자동 등록)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  allow_overwrite = true  # 덮어쓰기 허용
  name            = each.value.name # 레코드 이름
  records         = [each.value.record] # 레코드 값
  ttl             = 60  # 캐시 시간
  type            = each.value.type # 레코드 타입
  zone_id         = var.route53_zone_id # Route53 호스팅 영역 ID
}

# 3) 검증 대기 (이게 완료되어야 HTTPS 리스너가 생성됨)
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ------------------------------------------------------------------------------
# 3. ALB & Listener & Target Group
# ------------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${var.name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids


  tags = {
    Name = "${var.name}-lb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
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
    target_group_arn = aws_lb_target_group.was_tg.arn
  }
}

resource "aws_lb_target_group" "was_tg" {
  name     = "${var.name}-was-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30 # 30초마다 검사
    timeout             = 5  # 5초 안에 무응답시 실패
    healthy_threshold   = 2  # 죽었다 다시 살았을 때 2번 연속 성공해야 정상
    unhealthy_threshold = 2  # 멀쩡한 서버가 2번 실패시 다운으로 판단하여 트래픽 끊음
  }

  tags = {
    Name = "${var.name}-was-tg"
  }
}

# ------------------------------------------------------------------------------
# 4. IAM Role (WAS(EC2)를 위한 S3 접근 권한)
# ------------------------------------------------------------------------------

# 1. 역할(Role) 생성
resource "aws_iam_role" "was_role" {
  name = "was-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# 2. 정책(Policy) 생성 (S3 업로드/다운로드)
resource "aws_iam_policy" "was_s3_policy" {
  name        = "was-s3-upload-policy"
  description = "Allow WAS to upload/download to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",       
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

# 3. 연결(Attach)
resource "aws_iam_role_policy_attachment" "was_attach" {
  role       = aws_iam_role.was_role.name
  policy_arn = aws_iam_policy.was_s3_policy.arn
}

# 4. 프로파일(Profile) 생성 (EC2에 부착용)
resource "aws_iam_instance_profile" "was_profile" {
  name = "was-instance-profile"
  role = aws_iam_role.was_role.name
}

# ------------------------------------------------------------------------------
# 5. Launch Template 
# ------------------------------------------------------------------------------
resource "aws_launch_template" "was_lt" {
  name_prefix   = "${var.name}-was-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.was_profile.name
  }
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.was_sg.id]
  }

  tags = {
    Name = "${var.name}-was-lt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# 6. Auto Scaling Group 
# ------------------------------------------------------------------------------

resource "aws_autoscaling_group" "was_asg" {
  name                = "${var.name}-was-asg"
  desired_capacity    = var.asg_desired
  max_size            = var.asg_max
  min_size            = var.asg_min
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.was_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.was_tg.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.name}-was-instance"
    propagate_at_launch = true #ASG가 생성하는 EC2에 tag 붙히기
  }
}


