# 1. VPC ID
output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id
}

# 2. Public Subnets IDs
output "public_subnet_ids" {
  description = "Public Subnet ID 목록 [a zone, c zone]"
  value       = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}

# 3. WAS Subnets IDs
output "was_subnet_ids" {
  description = "WAS Subnet ID 목록 [a zone, c zone]"
  value       = [aws_subnet.was_a.id, aws_subnet.was_c.id]
}

# 4. DB Subnets IDs
output "db_subnet_ids" {
  description = "DB Subnet ID 목록 [a zone, c zone]"
  value       = [aws_subnet.db_a.id, aws_subnet.db_c.id]
}

