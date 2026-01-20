# --- 필수 ---
# name
# region
# vpc_id
# public_subnet_ids
# private_subnet_ids
# ami_id
# domain_name
# route53_zone_id
# bucket_name
# ecr_repository_url
# key_name
# --- 옵션 ---
# instance_type
# asg_max
# asg_min
# asg_desired
# container_env

variable "name" {
  description = "리소스 이름에 붙을 접두사 (예: dailo-prod)"
  type        = string
}

variable "region" {
  description = "AWS Region (예: ap-northeast-2)"
  type        = string
}


variable "vpc_id" {
  description = "VPC ID where ECS will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of Public Subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of Private Subnet IDs for ECS Nodes (ASG)"
  type        = list(string)
}

variable "ami_id" {
  description = "ECS에 사용할 AMI ID"
  type        = string
}

variable "domain_name" {
  description = "Domain name for ACM certificate (예: api.dailo.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for DNS validation"
  type        = string
}

variable "bucket_name" {
  description = "S3 Bucket Name for application access (IAM Policy)"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR Repository URL for pulling images"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

# --- Optional (기본값이 있어 입력 안 해도 되는 값들) ---

variable "instance_type" {
  description = "EC2 Instance Type for ECS Nodes"
  type        = string
  default     = "t3.medium" 
}

variable "asg_min" {
  description = "Minimum number of EC2 instances in ASG"
  type        = number
  default     = 1
}

variable "asg_max" {
  description = "Maximum number of EC2 instances in ASG"
  type        = number
  default     = 2
}

variable "asg_desired" {
  description = "Desired number of EC2 instances in ASG"
  type        = number
  default     = 1
}

variable "container_env" {
  description = "컨테이너에 주입할 환경변수 리스트 (Key-Value 쌍)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "container_port" {
  description = "컨테이너 내부에서 사용하는 포트 (예: Spring 8080, FastAPI 8000)"
  type        = number
  default     = 8080 # 기본값: 스프링
}

variable "cpu" {
  description = "컨테이너 할당 cpu"
  type        = number
  default     = 512
}
variable "memory" {
  description = "컨테이너 할당 memory"
  type        = number
  default     = 1024
}