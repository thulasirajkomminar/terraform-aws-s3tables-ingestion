# Register the table bucket with a custom vending role. The service-linked
# role cannot hold s3tables permissions, and without privileged access the
# federated catalog passes the caller's identity through instead of vending.
# Verify with both list-resources and describe-resource: each hides one flag.

data "aws_iam_policy_document" "lakeformation_assume_role" {
  statement {
    sid    = "LakeFormationAssumeRole"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
      "sts:SetContext",
      "sts:SetSourceIdentity",
    ]

    principals {
      type        = "Service"
      identifiers = ["lakeformation.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "lakeformation" {
  statement {
    sid       = "ListTableBuckets"
    effect    = "Allow"
    actions   = ["s3tables:ListTableBuckets"]
    resources = ["*"]
  }

  statement {
    sid    = "TableBucketDataAccess"
    effect = "Allow"

    actions = [
      "s3tables:GetNamespace",
      "s3tables:GetTable",
      "s3tables:GetTableBucket",
      "s3tables:GetTableData",
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
}

module "lakeformation_role" {
  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.5"

  name          = local.lakeformation_role_name
  assume_policy = data.aws_iam_policy_document.lakeformation_assume_role.json
  create_policy = true
  postfix       = false
  role_policy   = data.aws_iam_policy_document.lakeformation.json
  tags          = var.tags
}

# Applying this requires lakeformation:RegisterResourceWithPrivilegedAccess.
resource "aws_lakeformation_resource" "default" {
  arn                     = aws_s3tables_table_bucket.default.arn
  role_arn                = module.lakeformation_role.arn
  use_service_linked_role = false
  with_federation         = true
  with_privileged_access  = true
}

# Firehose Iceberg delivery requires ALL on the table; INSERT + ALTER fails
# with "Caller is required to have ALL permissions on the table".
resource "aws_lakeformation_permissions" "firehose_database" {
  principal   = module.firehose_role.arn
  permissions = ["DESCRIBE"]

  database {
    catalog_id = local.catalog_id
    name       = aws_s3tables_namespace.default.namespace
  }

  depends_on = [aws_lakeformation_resource.default]
}

resource "aws_lakeformation_permissions" "firehose_table" {
  principal   = module.firehose_role.arn
  permissions = ["ALL"]

  table {
    catalog_id    = local.catalog_id
    database_name = aws_s3tables_namespace.default.namespace
    name          = awscc_s3tables_table.default.table_name
  }

  depends_on = [aws_lakeformation_resource.default]
}

resource "aws_lakeformation_permissions" "reader_database" {
  for_each = toset(var.reader_principal_arns)

  principal   = each.value
  permissions = ["DESCRIBE"]

  database {
    catalog_id = local.catalog_id
    name       = aws_s3tables_namespace.default.namespace
  }

  depends_on = [aws_lakeformation_resource.default]
}

resource "aws_lakeformation_permissions" "reader_table" {
  for_each = toset(var.reader_principal_arns)

  principal   = each.value
  permissions = ["DESCRIBE", "SELECT"]

  table {
    catalog_id    = local.catalog_id
    database_name = aws_s3tables_namespace.default.namespace
    name          = awscc_s3tables_table.default.table_name
  }

  depends_on = [aws_lakeformation_resource.default]
}
