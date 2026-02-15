terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# 인증서는 반드시 us-east-1에 생성
provider "aws" {
  region = "us-east-1"
}

# 1. AWS에 이미 존재하는 메인 도메인(호스팅 영역) 정보 가져오기
data "aws_route53_zone" "main" {
  name         = "dailoapp.com"
  private_zone = false
}

# 2. 와일드카드 인증서 생성
resource "aws_acm_certificate" "cloudfront" {
  domain_name               = "dailoapp.com"
  subject_alternative_names = ["*.dailoapp.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "global-cloudfront-cert"
  }
}

# 3. DNS 검증 레코드 추가 (data로 가져온 zone_id 사용)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

# 4. 검증 완료 대기
resource "aws_acm_certificate_validation" "cloudfront" {
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}