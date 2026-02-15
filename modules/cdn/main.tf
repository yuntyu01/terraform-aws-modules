# modules/cdn/main.tf

# (provider 선언은 모듈 내부에 하지 않는 것이 정석이므로 제거함)

# 1. S3 버킷 & 보안 설정
resource "aws_s3_bucket" "static_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "static_bucket_block" {
  bucket                  = aws_s3_bucket.static_bucket.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.name}-s3-oac"
  description                       = "OAC for Static S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "s3_oac_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_policy" {
  bucket = aws_s3_bucket.static_bucket.id
  policy = data.aws_iam_policy_document.s3_oac_policy.json
}

# 2. CloudFront 배포 (외부에서 주입받은 인증서 ARN 사용)
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for ${var.name}"
  default_root_object = ""

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB-Origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = aws_s3_bucket.static_bucket.bucket_regional_domain_name
    origin_id                = "S3-Static-Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  aliases = [var.domain_name]

  # Default: ALB
  default_cache_behavior {
    target_origin_id         = "ALB-Origin"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  # Static: S3
  ordered_cache_behavior {
    path_pattern           = var.static_path_pattern
    target_origin_id       = "S3-Static-Origin"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # Grafana: ALB
  ordered_cache_behavior {
    path_pattern             = "/grafana/*"
    target_origin_id         = "ALB-Origin"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  price_class = "PriceClass_200"

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_cert_arn # 외부(Test 환경)에서 주입받음
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# 3. Route53 Alias (도메인 연결)
resource "aws_route53_record" "cdn_alias" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}