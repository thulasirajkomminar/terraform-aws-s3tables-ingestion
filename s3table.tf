# The table is an awscc resource because aws_s3tables_table cannot express a
# partition spec or sort order. The bucket and namespace stay on aws.

resource "aws_s3tables_table_bucket" "default" {
  name = local.table_bucket_name
}

resource "aws_s3tables_namespace" "default" {
  namespace        = local.namespace
  table_bucket_arn = aws_s3tables_table_bucket.default.arn
}

resource "awscc_s3tables_table" "default" {
  table_name        = local.table_name
  namespace         = aws_s3tables_namespace.default.namespace
  table_bucket_arn  = aws_s3tables_table_bucket.default.arn
  open_table_format = "ICEBERG"

  compaction = {
    status              = "enabled"
    target_file_size_mb = 256
  }

  snapshot_management = {
    status                 = "enabled"
    max_snapshot_age_hours = 168 # 7 days of time travel
    min_snapshots_to_keep  = 5
  }

  iceberg_metadata = {
    iceberg_schema = {
      # Field IDs are referenced by source_id in the partition spec and sort order.
      schema_field_list = [
        { id = 1, name = "ingest_ts", type = "timestamptz", required = true },  # when the pipeline received the reading
        { id = 2, name = "name", type = "string", required = true },            # human-readable sensor name or path
        { id = 3, name = "site_id", type = "string", required = true },         # tenant key, partition column
        { id = 4, name = "source_ts", type = "timestamptz", required = true },  # when the sensor observed the value
        { id = 5, name = "sensor_id", type = "string", required = true },       # sensor identity, sort column
        { id = 6, name = "value_boolean", type = "boolean", required = false }, # exactly one value_* column is set per row
        { id = 7, name = "value_double", type = "double", required = false },
        { id = 8, name = "value_string", type = "string", required = false },
      ]
    }

    # Dominant query: one site, a bounded time range, a few sensors.
    iceberg_partition_spec = {
      fields = [
        { field_id = 1000, name = "site_id", source_id = 3, transform = "identity" },
        { field_id = 1001, name = "source_ts_day", source_id = 4, transform = "day" },
      ]
    }

    iceberg_sort_order = {
      fields = [
        { source_id = 5, transform = "identity", direction = "asc", null_order = "nulls-last" },
        { source_id = 4, transform = "identity", direction = "asc", null_order = "nulls-last" },
      ]
    }

    table_properties = {
      "write.parquet.compression-codec" = "zstd"
    }
  }

  lifecycle {
    # Replacing the table destroys every Lake Formation grant and consumer
    # resource link that points at it.
    prevent_destroy = true

    # Engines mutate Iceberg metadata at runtime. Evolve the schema with
    # Athena ALTER TABLE, not here.
    ignore_changes = [iceberg_metadata]
  }
}
