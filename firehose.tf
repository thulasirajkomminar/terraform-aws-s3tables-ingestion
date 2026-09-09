resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.firehose_name}"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_cloudwatch_log_stream" "firehose_destination_delivery" {
  name           = "DestinationDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_cloudwatch_log_stream" "firehose_backup_delivery" {
  name           = "BackupDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

data "aws_iam_policy_document" "firehose" {
  statement {
    sid       = "KinesisRead"
    resources = [aws_kinesis_stream.default.arn]

    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
    ]
  }

  statement {
    sid       = "KmsDecrypt"
    resources = [aws_kms_key.default.arn]

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
  }

  statement {
    sid = "InvokeTransform"

    actions = [
      "lambda:InvokeFunction",
      "lambda:GetFunctionConfiguration",
    ]

    resources = [
      module.transform.arn,
      "${module.transform.arn}:*",
    ]
  }

  statement {
    sid       = "ErrorBucketRead"
    resources = [module.errors_bucket.arn]

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]
  }

  statement {
    sid       = "ErrorBucketWrite"
    resources = ["${module.errors_bucket.arn}/*"]

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:PutObject",
    ]
  }

  statement {
    sid = "S3TablesWrite"

    actions = [
      "s3tables:GetNamespace",
      "s3tables:GetTable",
      "s3tables:GetTableBucket",
      "s3tables:GetTableData",
      "s3tables:GetTableMetadata",
      "s3tables:GetTableMetadataLocation",
      "s3tables:ListNamespaces",
      "s3tables:ListTables",
      "s3tables:PutTableData",
      "s3tables:UpdateTableMetadataLocation",
    ]

    resources = [
      aws_s3tables_table_bucket.default.arn,
      "${aws_s3tables_table_bucket.default.arn}/table/*",
    ]
  }

  # All catalog references go through the federated s3tablescatalog.
  statement {
    sid = "GlueFederatedCatalog"

    actions = [
      "glue:GetCatalog",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:UpdateTable",
    ]

    resources = [
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog",
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog/s3tablescatalog",
      local.catalog_arn,
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:database/s3tablescatalog/${local.table_bucket_name}/${local.namespace}",
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:table/s3tablescatalog/${local.table_bucket_name}/${local.namespace}/*",
    ]
  }

  # Not resource-scopable; data access is governed by Lake Formation grants.
  statement {
    sid       = "LakeFormationDataAccess"
    resources = ["*"]

    actions = [
      "lakeformation:GetDataAccess",
      "lakeformation:GetTemporaryGlueTableCredentials",
    ]
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.firehose.arn}:log-stream:*"]
  }
}

module "firehose_role" {
  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.5"

  name                  = "${var.name}-firehose"
  create_policy         = true
  postfix               = false
  principal_identifiers = ["firehose.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.firehose.json
  tags                  = var.tags
}

resource "aws_kinesis_firehose_delivery_stream" "default" {
  name        = local.firehose_name
  destination = "iceberg"
  tags        = var.tags

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.default.arn
    role_arn           = module.firehose_role.arn
  }

  iceberg_configuration {
    role_arn           = module.firehose_role.arn
    catalog_arn        = local.catalog_arn
    buffering_size     = 5    # MB; small, frequent commits create snapshot churn faster than compaction absorbs it
    buffering_interval = 300  # seconds
    retry_duration     = 3600 # retry commits for an hour before diverting records to the error bucket
    s3_backup_mode     = "FailedDataOnly"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_destination_delivery.name
    }

    s3_configuration {
      role_arn            = module.firehose_role.arn
      bucket_arn          = module.errors_bucket.arn
      error_output_prefix = "errors/!{firehose:error-output-type}/"
      buffering_size      = 64
      buffering_interval  = 60
      compression_format  = "GZIP"

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.firehose_backup_delivery.name
      }
    }

    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${module.transform.arn}:$LATEST"
        }
      }
    }

    destination_table_configuration {
      database_name = aws_s3tables_namespace.default.namespace
      table_name    = awscc_s3tables_table.default.table_name
    }
  }

  # Firehose validates the Lake Formation grant on the table at creation.
  depends_on = [
    aws_lakeformation_permissions.firehose_table,
    aws_lambda_permission.firehose_invoke,
  ]
}
