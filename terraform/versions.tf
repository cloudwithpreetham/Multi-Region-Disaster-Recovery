terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state for now (single-developer, single-machine). Day 5 replaces this
  # with a remote backend (S3 + DynamoDB lock) so each region's state can be
  # applied independently and safely from CI or a second machine.
}
