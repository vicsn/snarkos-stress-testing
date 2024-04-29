# Terraform to launch ECS instances

This folder contains terraform you can use to launch multiple EC2 instances of the tx-cannon.

## Usage

1. Open the variables.tf file and change the variables to match your desired values:
    1. desired_count
    2. tx_cannon_command -- at a minimum, ensure the -e parameter has the url of your target endpoint
2. Run `terraform apply` in the `terraform` folder to provision your instances.
3. Run `terraform destroy` in the `terraform` folder to deprovision your instances.

## Relevant console links

### Cluster
Your task, service and cluster will be created in us-west-1, you can see it here: https://us-west-1.console.aws.amazon.com/ecs/v2/clusters?region=us-west-1 

### Logs
You can find log files under your service.  Click the service then click the logs tab you find under the service.  https://us-west-1.console.aws.amazon.com/ecs/v2/clusters/tx-cannon-cluster/services/tx-cannon-service/logs?region=us-west-1


