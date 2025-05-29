# ECS Cluster
data "aws_ecs_cluster" "existing_cluster" {
  cluster_name = var.existing_cluster_name
}

data "aws_region" "current" {}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source to get all the subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "tx_cannon_logs" {
  name              = "/ecs/${var.owner}-${var.devnet_name}-tx-cannon"
  retention_in_days = 1
}

# Task Definitions
resource "aws_ecs_task_definition" "tx_cannon_tasks" {
  for_each = var.tx_cannon_services

  family                   = "${var.owner}-${var.devnet_name}-tx-cannon-task-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "4096"  # 4 vCPU
  memory                   = "8192"  # 8 GB
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name  = "${var.owner}-tx-cannon-container"
      image = "${var.ecr_repository_url}:latest"
      environment = [
        { name = "SNARKOS_URL", value = "http://${aws_elb.snarkos_lb.dns_name}:3030" },
        { name = "TX_COMMAND", value = "${each.value.tx_command} ${local.snarkos_network}" }
      ]
      # NOTE: ECS logging configuration is commented out due to high costs.
      # Only enable if absolutely necessary for debugging.
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     awslogs-group         = aws_cloudwatch_log_group.tx_cannon_logs.name
      #     awslogs-region        = data.aws_region.current.name
      #     awslogs-stream-prefix = "service-${each.key}"
      #   }
      # }
    }
  ])
}

# ECS Services
resource "aws_ecs_service" "tx_cannon_services" {
  for_each = var.tx_cannon_services

  name            = "${var.owner}-${var.devnet_name}-tx-cannon-service-${each.key}"
  cluster         = data.aws_ecs_cluster.existing_cluster.id
  task_definition = aws_ecs_task_definition.tx_cannon_tasks[each.key].arn
  launch_type     = "FARGATE"
  desired_count   = each.value.task_count

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [module.sg.security_group_id]
    assign_public_ip = true
  }

  tags = {
    Name    = "${var.owner}-${var.devnet_name}-tx-cannon-service-${each.key}"
    Owner   = "${var.owner}"
    Devnet  = var.devnet_name
    Service = each.key
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.owner}-${var.devnet_name}-ecs-execution-role"

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

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
