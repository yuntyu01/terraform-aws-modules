terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [ aws.virginia ]
    }
  }
}

# ------------------------------------------------------------------------------
# 1. ACM Certificate (us-east-1 버지니아 리전)
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "cert" {
  provider          = aws.virginia # 버지니아 provider 강제 지정
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "${var.name}-cloudfront-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 2. DNS 검증 레코드 (Route53은 전세계 공통이라 서울 provider 써도 됨)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# 3. 검증 대기
resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.virginia # 인증서가 버지니아에 있으니 대기도 버지니아에서
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ------------------------------------------------------------------------------
# 2. CloudFront Distribution (CloudFront -> WAS)
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for ${var.name}"
  default_root_object = "" # API 서버라면 비워둠, 정적 웹사이트면 index.html

  # 원본(Origin) 설정: ALB
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only" # CloudFront -> ALB 구간 암호화
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  # 원본 2 (Origin-2) 설정: 이미지 및 파일용
  origin {
    domain_name              = aws_s3_bucket.static_bucket.bucket_regional_domain_name
    origin_id                = "S3-Static-Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }
  # 도메인 이름 연결 
  aliases = [var.domain_name]

  # 기본 캐시 동작 설정 (WAS용 - 로그인 등 동적 기능을 위해 헤더/쿠키 전달)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-Origin"

    # WAS는 보통 캐시를 끄거나, 모든 헤더를 넘겨야 함 (Managed-CachingDisabled 정책 사용 권장)
    # 아래 ID는 AWS가 미리 만들어둔 'CachingDisabled' 정책 ID임
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer (모든 헤더 전달)

    viewer_protocol_policy = "redirect-to-https" # HTTP로 오면 HTTPS로 강제 이동
    compress               = true                # Gzip 압축 전송
  }

  ordered_cache_behavior {
    path_pattern     = "/static/*" 
    target_origin_id = "S3-Static-Origin"

    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]

    # CachingOptimized (이미지용 권장 정책 - 캐싱 활성화)
    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    
    # CORS 문제가 있다면 아래 줄 주석 해제 (SimpleCORS)
    # origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c24c8f58b9"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # 전 세계 엣지 로케이션 사용 (가격 등급)
  price_class = "PriceClass_200" # 아시아 위치 엣지 로케이션

  # SSL 인증서 연결
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # 접근 제한 (제한 없음)
  restrictions {
    geo_restriction {
      restriction_type = "none" # ex( [kr] 같이 나라명 넣기
    }
  }
}

# ------------------------------------------------------------------------------
# 3. Route53 Alias (도메인 -> CloudFront 연결)
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 4. S3 Bucket & OAC (정적 파일용 / 이미지)
# ------------------------------------------------------------------------------

# OAC 생성 (CloudFront가 S3에 접근하기 위한 보안 자격 증명)
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.name}-oac"
  description                       = "OAC for Static S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always" # 모든 요청에 대해 항상 서명(인증)
  signing_protocol                  = "sigv4" # 서명 프로토콜
}
# S3 버킷 생성
resource "aws_s3_bucket" "static_bucket" {
  bucket = var.bucket_name
}

# (중요) 퍼블릭 액세스 차단 설정 (이걸 붙여야 진짜 안심!)
resource "aws_s3_bucket_public_access_block" "static_bucket_block" {
  bucket = aws_s3_bucket.static_bucket.id

  block_public_acls       = true  # 파일 공개 설정 방지
  ignore_public_acls      = true  # 이전 공개설정 파일 무시
  block_public_policy     = true  # 전체 공개 내용 추가 방지
  restrict_public_buckets = true  # 전체 공개시에도 아무나 못 들어옴
}

# S3 버킷 정책 (CloudFront만 접근 허용)
resource "aws_s3_bucket_policy" "static_policy" {
  bucket = aws_s3_bucket.static_bucket.id
  policy = data.aws_iam_policy_document.s3_oac_policy.json
}

data "aws_iam_policy_document" "s3_oac_policy" {
  statement {
    actions   = ["s3:GetObject"]  # 다운로드
    resources = ["${aws_s3_bucket.static_bucket.arn}/*"] # 모든 파일

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
