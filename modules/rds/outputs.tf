output "endpoint" {
  description = "RDS 접속 엔드포인트 (domain:port)"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS 접속 주소 (domain only)"
  value       = aws_db_instance.main.address
}