# main.tf
variable "aws_region" {
  default     = "us-west-2"
}

variable "collection_name" {
  default     = "snarkos-collection"
}

provider "aws" {
  region = var.aws_region
}

terraform {
  required_version = ">= 0.12"
}

# Creates an encryption security policy
resource "aws_opensearchserverless_security_policy" "encryption_policy" {
  name        = "snarkos-encryption-policy"
  type        = "encryption"
  description = "encryption policy for ${var.collection_name}"
  policy = jsonencode({
    Rules = [
      {
        Resource = [
          "collection/${var.collection_name}"
        ],
        ResourceType = "collection"
      }
    ],
    AWSOwnedKey = true
  })
}

# Creates a collection
resource "aws_opensearchserverless_collection" "collection" {
  name = var.collection_name

  depends_on = [aws_opensearchserverless_security_policy.encryption_policy]
}

# Creates a network security policy
resource "aws_opensearchserverless_security_policy" "snarkos" {
  name        = "snarkos-network-policy"
  type        = "network"
  description = "Public access"
  policy = jsonencode([
    {
      Description = "Public access to collection and Dashboards endpoint for snarkos collection",
      Rules = [
        {
          ResourceType = "collection",
          Resource = [
            "collection/${var.collection_name}"
          ]
        },
        {
          ResourceType = "dashboard"
          Resource = [
            "collection/${var.collection_name}"
          ]
        }
      ],
      AllowFromPublic = true
    }
  ])
}

# Gets access to the effective Account ID in which Terraform is authorized
data "aws_caller_identity" "current" {}

# Creates a data access policy
resource "aws_opensearchserverless_access_policy" "data_access_policy" {
  name        = "snarkos-data-access-policy"
  type        = "data"
  description = "allow index and collection access"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index",
          Resource = [
            "index/${var.collection_name}/*"
          ],
          Permission = [
            "aoss:*"
          ]
        },
        {
          ResourceType = "collection",
          Resource = [
            "collection/${var.collection_name}"
          ],
          Permission = [
            "aoss:*"
          ]
        }
      ],
      Principal = [
        data.aws_caller_identity.current.arn
      ]
    }
  ])
}