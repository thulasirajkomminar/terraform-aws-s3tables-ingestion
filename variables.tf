# Schema, partitioning, retention, Firehose buffering and table maintenance are
# fixed in the .tf files and functions/transform/transform.go, not variables.

variable "consumer_account_ids" {
  type        = list(string)
  description = "AWS account IDs that receive an account-level Lake Formation share with grant option, plus the table bucket policy their Lake Formation administrators need to grant onward. Pair with modules/consumer-share on the consumer side."
  default     = []

  validation {
    condition     = alltrue([for id in var.consumer_account_ids : can(regex("^\\d{12}$", id))])
    error_message = "Each consumer account ID must be a 12-digit AWS account ID."
  }
}

variable "consumer_principal_arns" {
  type        = list(string)
  description = "Optional. When set, the s3tables:GetTableData statement of the table bucket policy is granted to these principals instead of the consumer_account_ids account roots. The metadata actions stay at account scope."
  default     = []
}

variable "name" {
  type        = string
  description = "Base name for all resources: Kinesis stream, S3 Tables bucket, Firehose (<name>-ingestion), Lambda (<name>-transform), roles. Must be a valid S3 Tables bucket name: 3-40 lowercase letters, digits and hyphens."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "producer_account_ids" {
  type        = list(string)
  description = "AWS account IDs allowed to PutRecord(s) to the stream. Written into the Kinesis resource policy and the KMS key policy."
  default     = []

  validation {
    condition     = alltrue([for id in var.producer_account_ids : can(regex("^\\d{12}$", id))])
    error_message = "Each producer account ID must be a 12-digit AWS account ID."
  }
}

variable "reader_principal_arns" {
  type        = list(string)
  description = "IAM principal ARNs in this account granted Lake Formation DESCRIBE on the namespace and DESCRIBE + SELECT on the table. IAM Identity Center roles must use the full path form arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_..."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource."
  default     = {}
}

variable "transform_package_path" {
  type        = string
  description = "Path to a pre-built Lambda deployment zip containing an arm64 bootstrap binary. When null (default) the Go function in functions/transform is built at apply time, which requires go, make and zip on the machine running Terraform."
  default     = null
}
