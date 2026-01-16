output "cloudfront_id" {
  description = "생성된 CloudFront 배포의 ID (캐시 무효화 등에 사용)"
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_arn" {
  description = "CloudFront 배포의 ARN"
  value       = aws_cloudfront_distribution.cdn.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront의 기본 도메인 이름 (예: d1234.cloudfront.net)"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront의 Route53 Zone ID"
  value       = aws_cloudfront_distribution.cdn.hosted_zone_id
}