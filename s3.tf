# Records Firehose could not deliver after retry_duration land here, gzipped
# and prefixed by error type, for inspection and replay.

module "errors_bucket" {
  source  = "schubergphilis/mcaf-s3/aws"
  version = "~> 3.0"

  name          = local.error_bucket_name
  force_destroy = false
  kms_key_arn   = aws_kms_key.default.arn
  versioning    = true
  tags          = var.tags

  lifecycle_rule = [
    {
      id = "expire-failed-records"

      expiration = {
        days = 30
      }

      noncurrent_version_expiration = {
        noncurrent_days = 7
      }

      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    }
  ]
}
