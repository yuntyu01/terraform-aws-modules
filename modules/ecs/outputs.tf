# 1. 서비스 접속 주소 
output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

# 2. ECS 정보 (디버깅용)
output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "task_exec_role_arn" {
  value = aws_iam_role.ecs_exec_role.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "ecs_service_name" {
  description = "Name of the ECS Service"
  value       = aws_ecs_service.main.name
}

# 3. 보안 그룹 ID (다른 모듈에서 참조할 때 필요)
output "alb_security_group_id" {
  description = "Security Group ID of the ALB"
  value       = aws_security_group.alb_sg.id
}

output "ecs_node_security_group_id" {
  description = "Security Group ID of the ECS Nodes"
  value       = aws_security_group.ecs_node_sg.id
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = aws_lb.main.arn
}

output "http_listener_arn" {
  description = "The ARN of the HTTP (Port 80) Listener"
  value       = aws_lb_listener.http.arn 
}

output "asg_name" {
  description = "ecs autoscailing name"
  value       = aws_autoscaling_group.ecs_asg.name
}