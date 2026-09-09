# The Go function is built at apply time unless transform_package_path is set.

resource "terraform_data" "transform_build" {
  count = var.transform_package_path == null ? 1 : 0

  triggers_replace = {
    source_hash = local.transform_source_hash
  }

  provisioner "local-exec" {
    working_dir = local.transform_source_dir
    command     = "make build GOARCH=arm64"
  }
}

data "archive_file" "transform" {
  count = var.transform_package_path == null ? 1 : 0

  type             = "zip"
  source_file      = "${local.transform_source_dir}/dist/bootstrap"
  output_path      = "${local.transform_source_dir}/dist/transform.zip"
  output_file_mode = "0755"

  depends_on = [terraform_data.transform_build]
}

module "transform" {
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 4.1"

  name             = local.transform_name
  description      = "Firehose transform: map producer records onto the ${local.table_name} Iceberg schema"
  runtime          = "provided.al2023"
  handler          = "bootstrap"
  architecture     = "arm64"
  memory_size      = 256
  timeout          = 60
  log_retention    = 90
  filename         = local.transform_package_path
  source_code_hash = local.transform_package_hash
  tags             = var.tags
}

resource "aws_lambda_permission" "firehose_invoke" {
  statement_id  = "AllowFirehoseInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.transform.name
  principal     = "firehose.amazonaws.com"
  source_arn    = "arn:${local.partition}:firehose:${local.region}:${local.account_id}:deliverystream/${local.firehose_name}"
}
