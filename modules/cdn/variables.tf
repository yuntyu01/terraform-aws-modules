# name
# bucket_name
# domain_name
# route53_zone_id
# alb_dns_name

variable "name" {
  description = "리소스 이름에 붙을 접두사 (예: dailo-prod)"
  type        = string
}

variable "bucket_name" {
  description = "생성할 S3 버킷의 고유한 이름"
  type        = string
}

variable "domain_name" {
  description = "서비스할 도메인 주소"
  type        = string
}

variable "route53_zone_id" {
  description = "도메인 검증 및 Alias 레코드를 생성할 Route53 호스팅 영역 ID"
  type        = string
}

variable "alb_dns_name" {
  description = "CloudFront의 원본(Origin)으로 사용할 ALB의 DNS 주소"
  type        = string
}

