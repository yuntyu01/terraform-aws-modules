# name
# vpc_id
# public_subnet_ids
# private_subnet_ids
# ami_id
# instance_type
# key_name
# asg_desired
# asg_max
# asg_min
# domain_name
# route53_zone_id
# bucket_name

variable "name" {
  description = "리소스 이름에 붙을 접두사 (예: dailo-prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB를 배치할 Public Subnet ID 목록"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "WAS 인스턴스를 배치할 Private Subnet ID 목록"
  type        = list(string)
}

variable "ami_id" {
  description = "EC2에 사용할 AMI ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "EC2 접속용 키 페어 이름"
  type        = string
}

variable "asg_desired" {
  description = "ASG 희망 인스턴스 수"
  type        = number
  default     = 2
}

variable "asg_max" {
  description = "ASG 최대 인스턴스 수"
  type        = number
  default     = 4
}

variable "asg_min" {
  description = "ASG 최소 인스턴스 수"
  type        = number
  default     = 2
}

variable "domain_name" {
  description = "SSL 인증서를 발급받을 도메인 이름 (예: api.dailo.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "도메인을 관리하는 Route53 호스팅 영역 ID (Hosted Zone ID)"
  type        = string
}

variable "bucket_name" {
  description = "WAS가 접근할 S3 버킷 이름 (IAM Policy 생성용)"
  type        = string
}