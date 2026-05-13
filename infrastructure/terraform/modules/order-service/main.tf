locals {
  image_uri = var.container_image != "" ? var.container_image : "${aws_ecr_repository.order_service.repository_url}:latest"
}

# ── SQS ──────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "orders_dlq" {
  name                       = "${var.environment}-order-dlq"
  message_retention_seconds  = 1209600
}

resource "aws_sqs_queue" "orders" {
  name                       = "${var.environment}-order-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })
}

# ── SNS ──────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "order_notifications" {
  name = "${var.environment}-order-notifications"
}

resource "aws_sns_topic_subscription" "order_queue" {
  topic_arn = aws_sns_topic.order_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.orders.arn

  filter_policy = jsonencode({
    eventType = ["ORDER_PLACED", "ORDER_UPDATED", "ORDER_CANCELLED"]
  })
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.orders.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.orders.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_notifications.arn }
      }
    }]
  })
}

# ── ECR ──────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "order_service" {
  name                 = "${var.environment}-order-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_lifecycle_policy" "order_service" {
  repository = aws_ecr_repository.order_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ── IAM ──────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.environment}-order-service-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-order-service-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${var.environment}-order-service-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Scan", "dynamodb:Query",
        ]
        Resource = [
          var.orders_table_arn, "${var.orders_table_arn}/index/*",
          var.users_table_arn, "${var.users_table_arn}/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:SendMessage"]
        Resource = aws_sqs_queue.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.order_notifications.arn
      },
    ]
  })
}

# ── ECS ──────────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "bookstore" {
  name = "${var.environment}-bookstore"
}

resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/ecs/${var.environment}-order-service"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "order_service" {
  family                   = "${var.environment}-order-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "order-service"
    image     = local.image_uri
    essential = true

    portMappings = [{
      containerPort = 5001
      protocol      = "tcp"
    }]

    environment = [
      { name = "ORDERS_TABLE",              value = var.orders_table },
      { name = "USERS_TABLE",               value = var.users_table },
      { name = "ORDER_QUEUE_URL",           value = aws_sqs_queue.orders.url },
      { name = "NOTIFICATIONS_TOPIC_ARN",   value = aws_sns_topic.order_notifications.arn },
      { name = "AWS_DEFAULT_REGION",        value = var.aws_region },
      { name = "AWS_ENDPOINT_URL",          value = "http://localhost.localstack.cloud:4566" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.order_service.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "order-service"
      }
    }
  }])
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.environment}-bookstore-vpc" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.environment}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = { Name = "${var.environment}-public-b" }
}

resource "aws_security_group" "order_service" {
  name        = "${var.environment}-order-service-sg"
  description = "Order service ECS security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "order_service" {
  name            = "${var.environment}-order-service"
  cluster         = aws_ecs_cluster.bookstore.id
  task_definition = aws_ecs_task_definition.order_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.order_service.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_execution_policy]
}
