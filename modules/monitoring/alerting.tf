# SNS Topic
resource "aws_sns_topic" "alert_topic" {
  name = "${var.name}-alert-topic"
}

# ECS Task 최대 CPU 80% 이상
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "[URGENT] ${var.name}-High-CPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "80"
  alarm_actions       = [aws_sns_topic.alert_topic.arn]
  ok_actions          = [aws_sns_topic.alert_topic.arn]
  
  dimensions = {
    ClusterName = var.cluster_name
  }
}

# ECS Task 최대 Memory 80% 이상
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "[URGENT] ${var.name}-High-Memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization" 
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "80"
  alarm_actions       = [aws_sns_topic.alert_topic.arn]
  ok_actions          = [aws_sns_topic.alert_topic.arn]
  
  dimensions = {
    ClusterName = var.cluster_name
  }
}

# EC2 최대 CPU 80% 이상 (Auto Scaling Group 기준)
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "[URGENT] ${var.name}-EC2-Host-High-CPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  
  period              = "60"
  
  statistic           = "Maximum" 
  
  threshold           = "80"
  alarm_actions       = [aws_sns_topic.alert_topic.arn]
  ok_actions          = [aws_sns_topic.alert_topic.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

# EC2 호스트 메모리 알람 (ASG 기준, CloudWatch Agent)
resource "aws_cloudwatch_metric_alarm" "ec2_memory_high" {
  alarm_name          = "[URGENT] ${var.name}-EC2-Host-High-Memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  
  # 1. 네임스페이스와 지표 이름 변경 (Agent 설정과 일치)
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  period              = "60"
  statistic           = "Maximum" # ASG 내 서버 중 하나라도 메모리가 튀면 알람
  threshold           = "80"      # 메모리 80% 이상 
  
  alarm_actions       = [aws_sns_topic.alert_topic.arn]
  ok_actions          = [aws_sns_topic.alert_topic.arn]

  # 2. 차원(Dimension) 설정
  # 중요: 아래 User Data 설정에서 이 차원을 추가해줘야 매칭됩니다.
  dimensions = {
    AutoScalingGroupName = var.asg_name 
  }
}

# Lambda (Python 코드 압축)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/discord.py"
  output_path = "${path.module}/lambda.zip"
}

# Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.name}-alert-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ 
        Action = "sts:AssumeRole", 
        Effect = "Allow", 
        Principal = { Service = "lambda.amazonaws.com" } 
    }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "alert_sender" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.name}-alert-sender"
  role          = aws_iam_role.lambda_role.arn
  handler       = "discord.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = { DISCORD_WEBHOOK_URL = var.discord_webhook_url }
  }
}

# SNS -> Lambda 연결
resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_sender.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alert_topic.arn
}

resource "aws_sns_topic_subscription" "sub" {
  topic_arn = aws_sns_topic.alert_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alert_sender.arn
}