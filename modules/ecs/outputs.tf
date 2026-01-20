# 1. 서비스 접속 주소 (가장 중요)
output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "service_url" {
  description = "Full Service URL (HTTPS)"
  value       = "https://${var.domain_name}"
}

# 2. ECS 정보 (디버깅용)
output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = aws_ecs_cluster.main.name
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