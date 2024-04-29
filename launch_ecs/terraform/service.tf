resource "aws_ecs_service" "app_service" {
  name            = "tx-cannon-service"     # Name the service
  cluster         = "${aws_ecs_cluster.tx_cannon_cluster.id}"   # Reference the created Cluster
  task_definition = "${aws_ecs_task_definition.tx_cannon_task.arn}" # Reference the task that the service will spin up
  launch_type     = "FARGATE"
  desired_count   = var.desired_count 

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    assign_public_ip = true     # Provide the containers with public IPs
    #security_groups  = ["${aws_security_group.service_security_group.id}"] # Set up the security group
  }
}
