locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  error_bucket_name       = "${var.name}-ingestion-errors-${local.account_id}-${local.region}"
  firehose_name           = "${var.name}-ingestion"
  lakeformation_role_name = "S3TablesRoleForLakeFormation-${local.region}"
  namespace               = replace(local.region, "-", "_") # namespaces cannot contain hyphens
  table_bucket_name       = var.name
  table_name              = "sensor_readings"
  transform_name          = "${var.name}-transform"

  # S3 Tables metadata is exposed through a federated Glue catalog. Every Glue
  # and Lake Formation reference goes through it, never the default catalog.
  catalog_id  = "${local.account_id}:s3tablescatalog/${local.table_bucket_name}"
  catalog_arn = "arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog/s3tablescatalog/${local.table_bucket_name}"

  transform_source_dir = "${path.module}/functions/transform"

  transform_source_hash = sha1(join("", [
    for f in sort(fileset(local.transform_source_dir, "{*.go,go.mod,go.sum,Makefile}")) :
    filesha1("${local.transform_source_dir}/${f}")
  ]))

  transform_package_path = var.transform_package_path != null ? var.transform_package_path : data.archive_file.transform[0].output_path
  transform_package_hash = var.transform_package_path != null ? filebase64sha256(var.transform_package_path) : data.archive_file.transform[0].output_base64sha256

  consumer_data_read_principals = length(var.consumer_principal_arns) > 0 ? var.consumer_principal_arns : [
    for id in var.consumer_account_ids : "arn:${local.partition}:iam::${id}:root"
  ]
}
