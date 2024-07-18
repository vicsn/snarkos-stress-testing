resource "aws_ecs_task_definition" "tx_cannon_task" {
  family                   = "tx-cannon-task" # Name your task
  container_definitions    = jsonencode([
    {
      name      = "tx-cannon"
      image     = var.image
      cpu       = 8192
      memory    = 16384
      essential = true
      environment = [
        {
          name = "ALEO_COMMAND"
          value = var.tx_cannon_command
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/tx-cannon"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
  network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
  memory                   = 16384         # Specify the memory the container requires
  cpu                      = 8192         # Specify the CPU the container requires
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  runtime_platform {
    operating_system_family =  "LINUX"
    cpu_architecture        = "ARM64"
  }
}