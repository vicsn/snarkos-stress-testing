docker build -t stress .
docker tag stress:latest 942754456600.dkr.ecr.us-west-2.amazonaws.com/stress:latest
docker push 942754456600.dkr.ecr.us-west-2.amazonaws.com/stress:latest

docker-compose up --build --scale aleo-cannon=5
docker-compose up --scale aleo-cannon=5

docker build -t aleo-cannon-image .
docker run --rm aleo-cannon-image
docker run --rm -it aleo-cannon-image bash


docker run --rm stress


./random_unbond_cycle.sh http://34.202.237.104:3033 1

docker run --rm --env ALEO_COMMAND="./tests/rapid_committee_cycle/random_unbond_cycle.sh http://34.202.237.104:3033 1" stress


docker run --rm --env ALEO_COMMAND="./tests/rapid_committee_cycle/random_unbond_cycle.sh http://34.202.237.104:3033 1" stress

./tests/nonstop_delegators/run_fund_script.sh 1 http://34.202.237.104:3033 1


docker run --rm --env ALEO_COMMAND="./tests/nonstop_delegators/run_fund_script.sh 1 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033 1" stress


./tests/nonstop_delegators/run_fund_script.sh 3 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033 1

./tests/nonstop_delegators/run_fund_script.sh 10 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033 1

./tests/nonstop_delegators/run_fund_script.sh 10 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033 1

aws ecs run-task \
    --region 'us-west-2' \
    --cluster 'test-cannon2' \
    --task-definition 'cannon-custom-command-env' \
    --launch-type FARGATE \
    --overrides '{
        "containerOverrides": [
            {
                "name": "cannon-custom-command-env-container",
                "environment": [
                    {
                        "name": "ALEO_COMMAND",
                        "value": "echo hello world"
                    }
                ]
            }
        ]
    }' \
    --network-configuration '{
        "awsvpcConfiguration": {
            "subnets": [
                "subnet-0f750447303265132", "subnet-0ee43ce0bd98cfc59"
            ],
            "securityGroups": [
                "sg-0c20b423d78411ffb"
            ],
            "assignPublicIp": "ENABLED"
        }
    }'



    aws ecs run-task \
        --region 'us-west-2' \
        --cluster 'test-cannon2' \
        --task-definition 'cannon-custom-command-env' \
        --launch-type FARGATE \
        --overrides '{
            "containerOverrides": [
                {
                    "name": "cannon-custom-command-env-container",
                    "command": ["/bin/sh", "-c", "cd tests/nonstop_delegators && ./mass_bond_script.sh 0 250 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033"]
                }
            ]
        }' \
        --network-configuration '{
            "awsvpcConfiguration": {
                "subnets": [
                    "subnet-0f750447303265132", "subnet-0ee43ce0bd98cfc59"
                ],
                "securityGroups": [
                    "sg-0c20b423d78411ffb"
                ],
                "assignPublicIp": "ENABLED"
            }
        }'



            aws ecs run-task \
                --region 'us-west-2' \
                --cluster 'test-cannon2' \
                --task-definition 'cannon-custom-command-env' \
                --launch-type FARGATE \
                --count 2
                --overrides '{
                    "containerOverrides": [
                        {
                            "name": "cannon-custom-command-env-container",
                            "command": ["/bin/sh", "-c", "cd tests/nonstop_delegators && ./mass_bond_script.sh 2251 2495 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033"]
                        }
                    ]
                }' \
                --network-configuration '{
                    "awsvpcConfiguration": {
                        "subnets": [
                            "subnet-0f750447303265132", "subnet-0ee43ce0bd98cfc59"
                        ],
                        "securityGroups": [
                            "sg-0c20b423d78411ffb"
                        ],
                        "assignPublicIp": "ENABLED"
                    }
                }'


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
                            "command": ["/bin/sh", "-c", "cd tests/nonstop_delegators && ./mass_bond_script.sh 2251 2495 http://brentnet-v5-balance-2011764193.us-east-1.elb.amazonaws.com:3033"]
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
                  "command": ["/bin/sh", "-c", "cd tests/nonstop_delegators && ./mass_bond_script.sh 2251 2495 http://brentnet-v7-balancer-1913504089.us-east-1.elb.amazonaws.com:3033"]
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


      ./tests/nonstop_delegators/run_fund_script.sh 1 http://34.202.237.104:3033 1

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
                  "command": ["/bin/sh", "-c", "cd tests/mapping_attack && ./overload_sum.sh 5 http://mikenet-1997548764.us-east-2.elb.amazonaws.com:3033 1"]
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