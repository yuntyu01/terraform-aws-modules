# name
# vpc_id
# db_subnet_ids
# was_sg_id
# db_engine
# db_engine_version
# db_instance_class
# db_allocated_storage
# db_multi_az
# db_name
# db_username
# db_password

variable "name" {
  description = "리소스 이름의 접두사 (예: dailo-prod)"
  type        = string
}

variable "vpc_id" {
  description = "RDS 보안 그룹이 생성될 VPC의 ID"
  type        = string
}

variable "db_subnet_ids" {
  description = "RDS가 위치할 서브넷 ID 목록"
  type        = list(string)
}

variable "was_sg_id" {
  description = "DB 접속을 허용할 WAS의 보안그룹 ID"
  type        = string
}

# --- DB 엔진 및 성능 설정 ---
variable "db_engine" {
  description = "DB 엔진 (mysql, postgres 등)"
  type        = string
  default     = "mysql"
}

variable "db_engine_version" {
  description = "DB 엔진 버전"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "DB 인스턴스 사양"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS 인스턴스에 할당할 디스크 용량 (단위: GB)"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "고가용성 Multi-AZ 사용 여부"
  type        = bool
  default     = true
}

# --- 계정 정보 ---
variable "db_name" {
  type    = string
  default = "default_db" 
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  type      = string
  sensitive = true
}