# Customer-managed key. Cross-account producers need kms:GenerateDataKey on the
# key, which the AWS-managed aws/kinesis key cannot grant.

data "aws_iam_policy_document" "kms_key" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.producer_account_ids) > 0 ? [1] : []

    content {
      sid       = "AllowProducerAccountsViaKinesis"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
      ]

      principals {
        type        = "AWS"
        identifiers = [for id in var.producer_account_ids : "arn:${local.partition}:iam::${id}:root"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["kinesis.${local.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_kms_key" "default" {
  description         = "Encrypts the ${var.name} Kinesis stream and error bucket"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_key.json
  tags                = var.tags
}

resource "aws_kms_alias" "default" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.default.key_id
}
