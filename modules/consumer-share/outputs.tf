output "catalog_id" {
  description = "Producer's federated Glue catalog ID the link points at."
  value       = local.catalog_id
}

output "resource_link_name" {
  description = "Local Glue database name to query through, e.g. SELECT * FROM \"<resource_link_name>\".\"<table_name>\"."
  value       = aws_glue_catalog_database.link.name
}
