variable "aws_region" {
    default = "us-west-1"
    description = "The AWS region things are created in"
}

variable "desired_count" {
    description = "Number of instances to run"
    default = 2
}

variable "image" {
    #default = "149381701027.dkr.ecr.us-west-1.amazonaws.com/tx-cannon:latest"
    default = "public.ecr.aws/x1h2o8i6/tx-cannon:latest-arm64"
}

variable "tx_cannon_command" {
    default = "./tx-cannon batch-transfer -e http://snarkos-lb-931342428.us-east-2.elb.amazonaws.com:3030 -r 90000001 --funding-account APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH --amount 1 -w 5 -a aleo1hhzgdct6257yqj9wav3qqgnsjtnr2484frtqcjfva93yshywxypqs0wwa7"
}