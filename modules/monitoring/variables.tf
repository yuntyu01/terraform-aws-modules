# 1. 기본 설정 (General)
variable "name" {
  description = "생성될 리소스들의 이름 접두사 (예: test-grafana)"
  type        = string
}

variable "region" {
  description = "AWS 리전 (예: ap-northeast-2)"
  type        = string
}

variable "vpc_id" {
  description = "Grafana 서비스가 배포될 VPC의 ID"
  type        = string
}

# 2. ECS 및 ALB 종속성
variable "cluster_id" {
  description = "Grafana 서비스가 실행될 ECS 클러스터의 ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS 클러스터의 이름 (CloudWatch Log Group 식별 등에 사용)"
  type        = string
}

variable "ecs_exec_role_arn" {
  description = "ECS Task 실행 역할 ARN (이미지 Pull, 로그 전송 권한)"
  type        = string
}

variable "alb_arn" {
  description = "Grafana 접속을 위한 리스너 규칙을 추가할 ALB의 ARN"
  type        = string
}

variable "http_listener_arn" {
  description = "ALB의 80번 리스너 ARN (그라파나 룰 연결용)"
  type        = string
}

variable "alb_sg_id" {
  description = "Grafana 포트(3000) 인바운드를 허용할 ALB의 보안 그룹 ID"
  type        = string
}

variable "asg_name" {
  description = "ECS 클러스터의 이름 (CloudWatch Log Group 식별 등에 사용)"
  type        = string
}

variable "grafana_container_env" {
  description = "그라파나 컨테이너에 주입할 환경변수 리스트 (Key-Value 쌍)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# 3. 리소스 사양 (Resource Spec)
variable "cpu" {
  description = "Grafana 컨테이너에 할당할 CPU 유닛"
  type        = number
  default     = 512 
}

variable "memory" {
  description = "Grafana 컨테이너에 할당할 메모리 (MB)"
  type        = number
  default     = 512 
}


variable "discord_webhook_url" {
  description = "Grafana 알람을 전송할 Discord Webhook URL"
  type        = string
  sensitive   = true 
  default     = ""   
}

variable "log_retention_days" {
  description = "CloudWatch Logs 보관 기간 (일)"
  type        = number
  default     = 7    
}

variable "grafana_admin_password" {
  description = "Grafana 초기 접속용 관리자(admin) 비밀번호"
  type        = string
  sensitive   = true 
  default     = "admin1234!"
}
variable "app_log_group_name" {
  description = "S3로 아카이빙할 핵심 앱(Spring Boot)의 로그 그룹 이름"
  type        = string
}

variable "domain_name" {
  description = "서비스 도메인 주소"
  type        = string
}

variable "rds_endpoint" {
  type = string
}

variable "db_password" { # Init 컨테이너가 DB 접속할 때 필요
  type = string
}

variable "db_username" { # Init 컨테이너가 DB 접속할 때 필요
  type = string
}