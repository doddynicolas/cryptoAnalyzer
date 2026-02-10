variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "ecr_repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "frontend_image_tag" {
  type = string
}

variable "database_secret_arn" {
  type = string
}

resource "aws_ecs_cluster" "main" {
  name = "cryptoportfolio-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_iam_role" "execution_role" {
  name = "cryptoportfolio-${var.environment}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name = "cryptoportfolio-${var.environment}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "secrets_policy" {
  name = "cryptoportfolio-${var.environment}-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = var.database_secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_secrets_policy" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}

resource "aws_ecs_task_definition" "main" {
  family                   = "cryptoportfolio-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${var.ecr_repository_url}:${var.image_tag}"
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      secrets = [
        {
          name      = "DB_CREDENTIALS"
          valueFrom = var.database_secret_arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/cryptoportfolio-${var.environment}"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "backend"
        }
      }
    },
    {
      name  = "frontend"
      image = "${var.ecr_repository_url}-frontend:${var.frontend_image_tag}"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/cryptoportfolio-${var.environment}"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "frontend"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/cryptoportfolio-${var.environment}"
  retention_in_days = 30
}

resource "aws_ecs_service" "main" {
  name            = "cryptoportfolio-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.environment == "production" ? 3 : 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = var.security_group_ids
  }
}
