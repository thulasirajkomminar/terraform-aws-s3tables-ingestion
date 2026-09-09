// Command transform is the Firehose transform Lambda that maps producer
// records onto the S3 Tables Iceberg schema.
package main

import (
	"github.com/aws/aws-lambda-go/lambda"
	"go.uber.org/zap"
)

func main() {
	log := zap.Must(zap.NewProduction())
	defer func() { _ = log.Sync() }()

	lambda.Start(newHandler(log).Handle)
}
