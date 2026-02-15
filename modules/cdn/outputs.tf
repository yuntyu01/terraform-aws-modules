output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "static_bucket_name" {
  value = aws_s3_bucket.static_bucket.bucket
}