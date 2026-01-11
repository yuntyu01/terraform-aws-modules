# 실제 접속 주소
output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

# 3. 보안 그룹 ID (RDS 모듈에 넘겨줄 용도)
output "was_sg_id" {
  value = aws_security_group.was_sg.id
}

# Cloudfront or Route53 연결용 Zone ID
output "alb_zone_id" {
  description = "The canonical hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}