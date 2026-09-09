resource "aws_kinesis_stream" "default" {
  name             = var.name
  encryption_type  = "KMS"
  kms_key_id       = aws_kms_key.default.arn
  retention_period = 72 # a broken consumer can be fixed and replayed over a weekend
  tags             = var.tags

  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "OutgoingBytes",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
  ]

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}

# Producers keep their own identities; this is the allowlist. Encryption is
# covered separately by the key policy in kms.tf.
data "aws_iam_policy_document" "kinesis_producers" {
  count = length(var.producer_account_ids) > 0 ? 1 : 0

  statement {
    sid       = "AllowProducerAccountsPutRecords"
    effect    = "Allow"
    resources = [aws_kinesis_stream.default.arn]

    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      "kinesis:PutRecord",
      "kinesis:PutRecords",
    ]

    principals {
      type        = "AWS"
      identifiers = [for id in var.producer_account_ids : "arn:${local.partition}:iam::${id}:root"]
    }
  }
}

resource "aws_kinesis_resource_policy" "producers" {
  count = length(var.producer_account_ids) > 0 ? 1 : 0

  resource_arn = aws_kinesis_stream.default.arn
  policy       = data.aws_iam_policy_document.kinesis_producers[0].json
}
