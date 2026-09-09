# One region, one stream, one table. Producers in two other accounts write to
# the stream; one team in this account and one consumer account read the table.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.25"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.90"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# awscc has no per-resource region; it must match the aws provider's region.
provider "awscc" {
  region = "eu-central-1"
}

module "ingestion" {
  source = "../.."

  name                 = "sensor-readings-eu-central-1"
  consumer_account_ids = ["333333333333"] # pair with examples/consumer

  producer_account_ids = [
    "111111111111",
    "222222222222",
  ]

  # SSO roles need the full path including the Identity Center region segment.
  reader_principal_arns = [
    "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_DataScience_0123456789abcdef",
  ]

  tags = {
    Component = "sensor-readings"
    ManagedBy = "terraform"
  }
}

output "kinesis_stream_arn" {
  description = "Hand this to producers."
  value       = module.ingestion.kinesis_stream_arn
}

output "catalog_id" {
  description = "Consumers use this to build their resource link."
  value       = module.ingestion.catalog_id
}
