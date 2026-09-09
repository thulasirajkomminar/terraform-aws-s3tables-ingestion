variable "namespace" {
  type        = string
  description = "Namespace (Glue database) inside the producer's table bucket (root output namespace)."
}

variable "principal_arns" {
  type        = list(string)
  description = "IAM principal ARNs in this account that may query the shared table. IAM Identity Center roles must use the full path form arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_...; the pathless form is rejected with 'Invalid path for user'."
}

variable "producer_account_id" {
  type        = string
  description = "AWS account ID that owns the S3 Tables bucket."

  validation {
    condition     = can(regex("^\\d{12}$", var.producer_account_id))
    error_message = "producer_account_id must be a 12-digit AWS account ID."
  }
}

variable "resource_link_name" {
  type        = string
  description = "Name of the local Glue database that links to the producer's namespace. Defaults to namespace."
  default     = null
}

variable "table_bucket_name" {
  type        = string
  description = "Name of the producer's S3 Tables table bucket (root output table_bucket_name)."
}

variable "table_name" {
  type        = string
  description = "Name of the shared Iceberg table (root output table_name)."
  default     = "sensor_readings"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource."
  default     = {}
}
