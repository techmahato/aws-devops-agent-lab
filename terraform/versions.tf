terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Local backend for now. We did NOT assume a remote state bucket exists.
  # See README.md "Remote State" for the recommended secure S3 + DynamoDB setup
  # once you are ready to move state off the Bastion's local disk.
  # backend "s3" {}
}
