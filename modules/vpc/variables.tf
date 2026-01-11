# region
# name
# vpc_cidr
# public_subnet_a_cidr
# public_subnet_c_cidr
# was_subnet_a_cidr
# was_subnet_c_cidr
# db_subnet_a_cidr
# db_subnet_c_cidr

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "name" {
  description = "리소스 이름에 붙을 접두사, 프로젝트 명 (예: Dailo-prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

# Public Subnets
variable "public_subnet_a_cidr" {
  description = "Public Subnet A의 CIDR"
  type        = string
}

variable "public_subnet_c_cidr" {
  description = "Public Subnet C의 CIDR"
  type        = string
}

# WAS Subnets
variable "was_subnet_a_cidr" {
  description = "WAS Subnet A의 CIDR"
  type        = string
}

variable "was_subnet_c_cidr" {
  description = "WAS Subnet C의 CIDR"
  type        = string
}

# DB Subnets (Private)
variable "db_subnet_a_cidr" {
  description = "DB Subnet A의 CIDR"
  type        = string
}
variable "db_subnet_c_cidr" {
  description = "DB Subnet C의 CIDR"
  type        = string
}


