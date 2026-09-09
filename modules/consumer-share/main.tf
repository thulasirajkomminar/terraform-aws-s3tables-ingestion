# Consumer side of the cross-account share. Apply as a Lake Formation data lake
# administrator in an account listed in the root's consumer_account_ids, in the
# same region as the producer's table. Query through the resource link only,
# from an Athena workgroup with requester pays disabled.

locals {
  catalog_id         = "${var.producer_account_id}:s3tablescatalog/${var.table_bucket_name}"
  resource_link_name = coalesce(var.resource_link_name, var.namespace)
}

resource "aws_glue_catalog_database" "link" {
  name = local.resource_link_name
  tags = var.tags

  target_database {
    catalog_id    = local.catalog_id
    database_name = var.namespace
  }
}

# Three grants per principal. A missing grant on any hop surfaces in Athena as
# TABLE_NOT_FOUND, not as a permission error.
resource "aws_lakeformation_permissions" "link_describe" {
  for_each = toset(var.principal_arns)

  principal   = each.value
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.link.name
  }
}

resource "aws_lakeformation_permissions" "target_database_describe" {
  for_each = toset(var.principal_arns)

  principal   = each.value
  permissions = ["DESCRIBE"]

  database {
    catalog_id = local.catalog_id
    name       = var.namespace
  }
}

resource "aws_lakeformation_permissions" "target_table_select" {
  for_each = toset(var.principal_arns)

  principal   = each.value
  permissions = ["DESCRIBE", "SELECT"]

  table {
    catalog_id    = local.catalog_id
    database_name = var.namespace
    name          = var.table_name
  }
}
