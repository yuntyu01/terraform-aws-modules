output "repository_url" {
  description = "ECR Repository URL (ECS에서 사용)"
  value       = aws_ecr_repository.main.repository_url
}