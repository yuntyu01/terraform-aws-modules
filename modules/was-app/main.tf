# 1. Security Group - 2개 ([Pub]alb 1개, [Pri]was 1개)
# 2. ALB & Listener & Target Group - 1개 (Listener - http, TG - was.sg)
# 3. Launch Template 
# 4. Auto Scaling Group 

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
    cidr_blocks = [aws_security_group.alb_sg.id]
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
# 2. ALB & Listener & Target Group
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
# 3. Launch Template 
# ------------------------------------------------------------------------------
resource "aws_launch_template" "was_lt" {
  name_prefix   = "${var.name}-was-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

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
# 4. Auto Scaling Group 
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


