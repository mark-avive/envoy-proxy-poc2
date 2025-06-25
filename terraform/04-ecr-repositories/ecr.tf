# ECR Repository for Server Application
resource "aws_ecr_repository" "envoy_poc_app_repository" {
  name                 = local.app_repository_name
  image_tag_mutability = local.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = local.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name        = local.app_repository_name
    Application = "server-app"
    Purpose     = "WebSocket-Server-Application"
  })
}

# ECR Repository for Client Application
resource "aws_ecr_repository" "envoy_poc_client_repository" {
  name                 = local.client_repository_name
  image_tag_mutability = local.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = local.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name        = local.client_repository_name
    Application = "client-app"
    Purpose     = "WebSocket-Client-Application"
  })
}

# Lifecycle Policy for App Repository
resource "aws_ecr_lifecycle_policy" "envoy_poc_app_lifecycle" {
  repository = aws_ecr_repository.envoy_poc_app_repository.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${local.lifecycle_policy_days} days of images"
        selection = {
          tagStatus     = "any"
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = local.lifecycle_policy_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lifecycle Policy for Client Repository
resource "aws_ecr_lifecycle_policy" "envoy_poc_client_lifecycle" {
  repository = aws_ecr_repository.envoy_poc_client_repository.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${local.lifecycle_policy_days} days of images"
        selection = {
          tagStatus     = "any"
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = local.lifecycle_policy_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
