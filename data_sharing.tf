# Cross-account sharing, producer side: account-level Lake Formation grants
# with grant option, plus the table bucket policy the consumer's Lake
# Formation administrators need before they can grant onward.
#
# Lake Formation validates consumer-side grants with a federated glue:GetTable
# as the calling principal. The RAM share only carries glue:* ARNs, so without
# this bucket policy every consumer-side grant fails with
# "Insufficient Glue permissions to access table".

data "aws_iam_policy_document" "table_bucket" {
  count = length(var.consumer_account_ids) > 0 ? 1 : 0

  # Metadata actions, account scoped. This is what grant validation needs.
  statement {
    sid    = "ConsumerMetadataRead"
    effect = "Allow"

    actions = [
      "s3tables:GetNamespace",
      "s3tables:GetTable",
      "s3tables:GetTableBucket",
      "s3tables:GetTableMetadataLocation",
      "s3tables:ListNamespaces",
      "s3tables:ListTables",
    ]

    resources = [
      aws_s3tables_table_bucket.default.arn,
      "${aws_s3tables_table_bucket.default.arn}/table/*",
    ]

    principals {
      type        = "AWS"
      identifiers = [for id in var.consumer_account_ids : "arn:${local.partition}:iam::${id}:root"]
    }
  }

  # GetTableData is required for federated reads but bypasses Lake Formation,
  # so it is scoped to specific principals when consumer_principal_arns is set.
  # It is a CloudTrail data event: its denial does not appear in Event History.
  statement {
    sid     = "ConsumerDataRead"
    effect  = "Allow"
    actions = ["s3tables:GetTableData"]

    resources = [
      aws_s3tables_table_bucket.default.arn,
      "${aws_s3tables_table_bucket.default.arn}/table/*",
    ]

    principals {
      type        = "AWS"
      identifiers = local.consumer_data_read_principals
    }
  }
}

resource "aws_s3tables_table_bucket_policy" "default" {
  count = length(var.consumer_account_ids) > 0 ? 1 : 0

  table_bucket_arn = aws_s3tables_table_bucket.default.arn
  resource_policy  = data.aws_iam_policy_document.table_bucket[0].json
}

# Only account-level cross-account grants can carry grant option.
resource "aws_lakeformation_permissions" "consumer_database" {
  for_each = toset(var.consumer_account_ids)

  principal                     = each.value
  permissions                   = ["DESCRIBE"]
  permissions_with_grant_option = ["DESCRIBE"]

  database {
    catalog_id = local.catalog_id
    name       = aws_s3tables_namespace.default.namespace
  }

  depends_on = [aws_lakeformation_resource.default]
}

resource "aws_lakeformation_permissions" "consumer_table" {
  for_each = toset(var.consumer_account_ids)

  principal                     = each.value
  permissions                   = ["DESCRIBE", "SELECT"]
  permissions_with_grant_option = ["DESCRIBE", "SELECT"]

  table {
    catalog_id    = local.catalog_id
    database_name = aws_s3tables_namespace.default.namespace
    name          = awscc_s3tables_table.default.table_name
  }

  depends_on = [aws_lakeformation_resource.default]
}
