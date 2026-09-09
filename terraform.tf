terraform {
  required_version = ">= 1.9"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.25"
    }
    # aws_s3tables_table cannot express a partition spec or sort order.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.90"
    }
  }
}
