variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
}

variable "instance_type" {
  description = "Type of instance to deploy"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  type        = string
}

variable "region_index" {
  description = "Index of the region"
  type        = number
}
