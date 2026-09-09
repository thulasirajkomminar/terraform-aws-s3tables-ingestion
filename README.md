# terraform-aws-s3tables-ingestion

Streaming ingestion of sensor readings into an Apache Iceberg table on Amazon S3 Tables: one Kinesis stream, one Firehose delivery stream with a Go transform Lambda, one partitioned table per region, governed by Lake Formation and shareable across accounts.

**This is a template, not a library module.** It is the complete implementation of one specific design, with the schema fixed in both the Terraform table definition and the Go transform. Copy the repository, change the columns and names to yours, and deploy it from one of the `examples/`.

The design and every decision in it is explained in a five-part blog series. Read it before you edit anything:

1. [When 90 Buckets Become a Bottleneck in an IIoT Data Platform](https://www.thulasirajkomminar.com/posts/when-90-buckets-become-a-bottleneck-in-an-iiot-data-platform/): why one table per region
2. [Consolidating Streaming Ingestion with Kinesis Firehose and Apache Iceberg](https://www.thulasirajkomminar.com/posts/consolidating-streaming-ingestion-with-kinesis-firehose-and-apache-iceberg/): the pipeline in this repo
3. [Designing One Iceberg Table for Ninety Sites](https://www.thulasirajkomminar.com/posts/designing-one-iceberg-table-for-ninety-sites/): the schema, partitioning, and why the table is an `awscc` resource
4. [Sharing S3 Tables Across Accounts with Lake Formation](https://www.thulasirajkomminar.com/posts/sharing-s3-tables-across-accounts-with-lake-formation/): `data_sharing.tf`, `modules/consumer-share`, and every gotcha
5. [Debugging a Federated AccessDenied, Layer by Layer](https://www.thulasirajkomminar.com/posts/debugging-a-federated-accessdenied-layer-by-layer/): how to debug it when it breaks

## Using this repo

1. **Copy it.** Use GitHub's *Use this template* button, or clone and re-init:

   ```sh
   git clone https://github.com/thulasirajkomminar/terraform-aws-s3tables-ingestion my-ingestion
   cd my-ingestion && rm -rf .git && git init
   ```

2. **Change the schema in the two places that must agree.** Iceberg columns, partition spec, and sort order live in [`s3table.tf`](s3table.tf). The producer record mapping, validation, and type routing live in [`functions/transform/transform.go`](functions/transform/transform.go) and its tests. Output JSON keys from the Lambda must match Iceberg column names exactly. Run `make -C functions/transform lint test` after every edit.

3. **Change what is yours.** Names, regions, producer accounts, reader principals, and consumer accounts live in the example you deploy from. Every input is described in [`variables.tf`](variables.tf). Operational choices such as Firehose buffering, compaction, and Lambda sizing are fixed in the `.tf` files; edit them there.

4. **Deploy from an example.** [examples/single-region](examples/single-region) for one region, [examples/multi-region](examples/multi-region) for the awscc provider-alias-per-region pattern, [examples/consumer](examples/consumer) for the account that reads the table. Each is a root module with `source = "../.."`. The applying principal must be a Lake Formation data lake administrator.

5. **Delete what you don't need.** No cross-account consumers? Drop `data_sharing.tf` and `modules/consumer-share`. Already have a KMS key or a stream? Delete `kms.tf` or the stream in `kinesis.tf` and point the remaining references at your ARN.

The transform Lambda is built during `terraform apply`, which needs `go` 1.24+, `make`, and `zip` on the machine running Terraform. To skip that, run `make -C functions/transform package` once and set `transform_package_path` to the resulting zip.

## Producer record contract

Producers write one JSON object per Kinesis record:

```json
{
  "name":      "boiler-3/steam-pressure",
  "data_type": "float",
  "site_id":   "site-01",
  "sensor_id": "6f1c2a9e-3b8d-4f0a-9c7e-2d5b8a1f4e63",
  "timestamp": 1718100000000,
  "value":     4.21
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `name` | string | required; human-readable sensor name or path |
| `data_type` | `"float"` / `"boolean"` / `"string"` | required; routes `value` into one typed column |
| `site_id` | string | required; tenant key and partition column |
| `sensor_id` | string | required; stable identity of the sensor, sort column |
| `timestamp` | int64 | required; **milliseconds** since epoch, when the sensor observed the value |
| `value` | number / bool / string / null | coerced to `data_type`; `"12.5"` and `"true"` are accepted, `"abc"` for a float is not |

Records that break this contract are **Dropped** and logged with `site_id`, `sensor_id`, and a truncated payload. Anything unexpected is **ProcessingFailed** and lands in the error bucket under `errors/<error-type>/` for replay.

## License

[Apache 2.0](LICENSE)
