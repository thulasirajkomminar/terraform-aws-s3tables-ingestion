# One identical stack per region, stamped from the same module. The aws
# provider (v6+) could use a per-resource region, but awscc cannot, so each
# region gets a pair of provider aliases and both are passed to the module.

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

locals {
  producer_account_ids = ["111111111111", "222222222222"]
  consumer_account_ids = ["333333333333"]

  tags = {
    Component = "sensor-readings"
    ManagedBy = "terraform"
  }
}

# ── eu-central-1 ─────────────────────────────────────────────────────────

provider "aws" {
  region = "eu-central-1"
}

provider "awscc" {
  region = "eu-central-1"
}

module "ingestion_eu_central_1" {
  source = "../.."

  name                 = "sensor-readings-eu-central-1"
  producer_account_ids = local.producer_account_ids
  consumer_account_ids = local.consumer_account_ids
  tags                 = local.tags
}

# ── us-west-2 ────────────────────────────────────────────────────────────

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

provider "awscc" {
  alias  = "us_west_2"
  region = "us-west-2"
}

module "ingestion_us_west_2" {
  source = "../.."

  providers = {
    aws   = aws.us_west_2
    awscc = awscc.us_west_2
  }

  name                 = "sensor-readings-us-west-2"
  producer_account_ids = local.producer_account_ids
  consumer_account_ids = local.consumer_account_ids
  tags                 = local.tags
}

output "kinesis_stream_arns" {
  value = {
    eu-central-1 = module.ingestion_eu_central_1.kinesis_stream_arn
    us-west-2    = module.ingestion_us_west_2.kinesis_stream_arn
  }
}
