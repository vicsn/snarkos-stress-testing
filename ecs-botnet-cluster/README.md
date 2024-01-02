## (Optional) tx-cannon ECS "botnet" cluster

In the `ecs-botnet-cluster` directory run Terraform to set up an ECS cluster and task definition for running scaled [tx-cannon](https://github.com/AleoHQ/tx-cannon) stress tests.

```bash
cd ecs-botnet-cluster
terraform init
terraform apply
```

This will set up the cluster and task definition. ECS tasks can be run from the CLI:

```bash
aws ecs run-task \
                --region 'us-east-2' \
                --cluster 'tx-cannon' \
                --task-definition 'tx-cannon-2vCPU-16GB' \
                --launch-type FARGATE \
                --count 1 \
                --overrides '{
                    "containerOverrides": [
                        {
                            "name": "tx-cannon-repo-latest",
                            "command": ["/bin/sh", "-c", "tx-cannon bulk-execute --test tests/hello_hello/hello_hello_flood.toml --flood -e http://snarkos-lb-786949557.us-east-2.elb.amazonaws.com"]
                        }
                    ]
                }' \
                --network-configuration '{
                    "awsvpcConfiguration": {
                        "subnets": [
                            "subnet-0f75eb61126c94ee8", "subnet-021f7014e19e051f3","subnet-00279334e1be83b36"
                        ],
                        "securityGroups": [
                            "sg-00246c5b5b63d2bdc"
                        ],
                        "assignPublicIp": "ENABLED"
                    }
                }'
```

A task can have a max count of 10 and will shut down when it is complete.

To have a higher count and have the `tx-cannon` run over and over, you can create a service:

```bash
aws ecs create-service \
                  --region 'us-east-2' \
                  --cluster 'tx-cannon' \
                  --service-name 'hello_hello_service' \
                  --task-definition 'tx-cannon-2vCPU-16GB' \
                  --desired-count 2000 \
                  --launch-type FARGATE \
                  --network-configuration '{
                      "awsvpcConfiguration": {
                          "subnets": [
                              "subnet-0f75eb61126c94ee8", "subnet-021f7014e19e051f3","subnet-00279334e1be83b36"
                          ],
                          "securityGroups": [
                              "sg-00246c5b5b63d2bdc"
                          ],
                          "assignPublicIp": "ENABLED"
                      }
                  }'
```