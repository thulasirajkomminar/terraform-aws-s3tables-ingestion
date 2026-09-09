output "catalog_id" {
  description = "Federated Glue catalog ID (<account>:s3tablescatalog/<bucket>). Consumers use this as target_database.catalog_id in their resource link."
  value       = local.catalog_id
}

output "error_bucket_name" {
  description = "Bucket receiving records Firehose could not deliver."
  value       = module.errors_bucket.name
}

output "kinesis_stream_arn" {
  description = "Stream producers write to. Hand this to producers."
  value       = aws_kinesis_stream.default.arn
}

output "namespace" {
  description = "Namespace (Glue database) containing the table."
  value       = aws_s3tables_namespace.default.namespace
}

output "table_bucket_name" {
  description = "S3 Tables table bucket. Consumers need this to build the federated catalog ID."
  value       = aws_s3tables_table_bucket.default.name
}

output "table_name" {
  description = "Iceberg table name."
  value       = awscc_s3tables_table.default.table_name
}
