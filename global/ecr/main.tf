variable "name" {
  description = "Repository name"
  type        = string
}

resource "aws_ecr_repository" "main" {
  name                 = var.name
  image_tag_mutability = "MUTABLE" # 태그 덮어쓰기 허용

  # 이미지 업로드 시 보안 취약점 스캔 
  image_scanning_configuration {
    scan_on_push = true
  }

  # 레포지토리 삭제 시 내부 이미지가 있어도 강제 삭제 
  force_delete = true

  tags = {
    Name = var.name
  }
}

# 2. 수명 주기 정책 (Lifecycle Policy)
resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      # [규칙 1] 'dev-'로 시작하는 태그는 14일 지나면 삭제 (개발용)
      {
        rulePriority = 1
        description  = "Expire dev images older than 14 days"
        selection    = {
          tagStatus      = "tagged"
          tagPrefixList  = ["dev-"]
          countType      = "sinceImagePushed"
          countUnit      = "days"
          countNumber    = 14
        }
        action = {
          type = "expire"
        }
      },
      # [규칙 2] 태그가 없는(Untagged) 이미지는 7일 뒤 삭제
      {
        rulePriority = 2
        description  = "Remove untagged images immediately"
        selection    = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
     
    ]
  })
}