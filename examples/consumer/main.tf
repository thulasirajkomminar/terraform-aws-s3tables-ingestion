# Consumer account (333333333333 in the other examples). Run as a Lake
# Formation data lake administrator, in the same region as the producer table.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.25"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "share" {
  source = "../../modules/consumer-share"

  producer_account_id = "123456789012"
  table_bucket_name   = "sensor-readings-eu-central-1" # root module output table_bucket_name
  namespace           = "eu_central_1"                 # root module output namespace
  table_name          = "sensor_readings"

  principal_arns = [
    "arn:aws:iam::333333333333:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_Analyst_fedcba9876543210",
  ]

  tags = {
    Component = "sensor-readings"
    ManagedBy = "terraform"
  }
}

output "query_hint" {
  value = "SELECT * FROM \"${module.share.resource_link_name}\".\"sensor_readings\" WHERE site_id = 'site-01' LIMIT 10"
}
