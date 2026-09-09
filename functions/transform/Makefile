# Build the Firehose transform as a Lambda custom-runtime binary.
#
#   make build            -> dist/bootstrap (linux/arm64 by default)
#   make build GOARCH=amd64
#   make package          -> dist/transform.zip (for transform_package_path)
#   make lint fmt test

GOOS   ?= linux
GOARCH ?= arm64
DIST   := dist

.PHONY: build package test lint fmt clean

build:
	@mkdir -p $(DIST)
	GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -tags lambda.norpc -o $(DIST)/bootstrap .

package: build
	@rm -f $(DIST)/transform.zip
	@cd $(DIST) && zip -q -r9 transform.zip bootstrap
	@echo "$(DIST)/transform.zip"

test:
	go test ./... -race -cover

lint:
	golangci-lint run ./...

fmt:
	golangci-lint fmt ./...

clean:
	rm -rf $(DIST)
