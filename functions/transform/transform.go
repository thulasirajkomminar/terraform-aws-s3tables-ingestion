package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"go.uber.org/zap"
)

const (
	dataTypeFloat   = "float"
	dataTypeBoolean = "boolean"
	dataTypeString  = "string"

	microsPerMilli  = 1000
	floatBitSize    = 64
	logPayloadLimit = 256
)

// errQuality marks a malformed record. These are dropped, not failed.
var errQuality = errors.New("data quality")

var (
	errMissingField    = errors.New("missing field")
	errUnknownDataType = errors.New("unknown data_type")
	errNotFloat        = errors.New("value not a float")
	errNotBoolean      = errors.New("value not a boolean")
	errUnsupportedType = errors.New("unsupported type")
)

// inputRecord is the producer contract. Timestamp is milliseconds since epoch.
type inputRecord struct {
	Name      string `json:"name"`
	DataType  string `json:"data_type"` // "float" | "boolean" | "string"
	SiteID    string `json:"site_id"`
	SensorID  string `json:"sensor_id"`
	Timestamp int64  `json:"timestamp"`
	Value     any    `json:"value"`
}

// outputRecord is the Iceberg table schema. Timestamps are microseconds since
// epoch, as Firehose expects for timestamptz. Exactly one value_* column is set.
type outputRecord struct {
	IngestTs     int64    `json:"ingest_ts"`
	Name         string   `json:"name"`
	SiteID       string   `json:"site_id"`
	SourceTs     int64    `json:"source_ts"`
	SensorID     string   `json:"sensor_id"`
	ValueBoolean *bool    `json:"value_boolean"`
	ValueDouble  *float64 `json:"value_double"`
	ValueString  *string  `json:"value_string"`
}

type handler struct {
	log *zap.Logger
}

func newHandler(log *zap.Logger) *handler {
	return &handler{log: log}
}

// Handle transforms one Firehose batch. Quality errors are Dropped so they
// never look like pipeline failures. Anything else is ProcessingFailed, which
// sends the original record to the error bucket for replay.
func (h *handler) Handle(_ context.Context, event *events.KinesisFirehoseEvent) (events.KinesisFirehoseResponse, error) {
	now := time.Now()
	out := events.KinesisFirehoseResponse{
		Records: make([]events.KinesisFirehoseResponseRecord, 0, len(event.Records)),
	}

	var dropped, failed int

	for i := range event.Records {
		record := &event.Records[i]

		in, transformed, err := transform(record.Data, now)
		if err == nil {
			out.Records = append(out.Records, events.KinesisFirehoseResponseRecord{
				RecordID: record.RecordID,
				Result:   events.KinesisFirehoseTransformedStateOk,
				Data:     transformed,
			})

			continue
		}

		result := events.KinesisFirehoseTransformedStateProcessingFailed
		if errors.Is(err, errQuality) {
			result = events.KinesisFirehoseTransformedStateDropped
			dropped++
		} else {
			failed++
		}

		h.logRejected(record, &in, result, err)

		out.Records = append(out.Records, events.KinesisFirehoseResponseRecord{
			RecordID: record.RecordID,
			Result:   result,
			Data:     []byte{},
		})
	}

	if dropped > 0 || failed > 0 {
		h.log.Warn("batch had rejected records",
			zap.Int("records", len(event.Records)),
			zap.Int("dropped_quality", dropped),
			zap.Int("processing_failed", failed),
		)
	}

	return out, nil
}

func (h *handler) logRejected(record *events.KinesisFirehoseEventRecord, in *inputRecord, result string, err error) {
	h.log.Warn("record rejected",
		zap.String("result", result),
		zap.String("shard", record.KinesisFirehoseRecordMetadata.ShardID),
		zap.String("sequence", record.KinesisFirehoseRecordMetadata.SequenceNumber),
		zap.String("site_id", in.SiteID),
		zap.String("sensor_id", in.SensorID),
		zap.String("payload", truncate(record.Data, logPayloadLimit)),
		zap.Error(err),
	)
}

// transform maps one producer record onto the table schema. ingest_ts is
// stamped here, not taken from the producer.
func transform(payload []byte, now time.Time) (inputRecord, []byte, error) {
	var in inputRecord

	err := json.Unmarshal(payload, &in)
	if err != nil {
		return in, nil, fmt.Errorf("%w: decode: %w", errQuality, err)
	}

	err = validate(&in)
	if err != nil {
		return in, nil, err
	}

	out := outputRecord{
		IngestTs: now.UnixMicro(),
		Name:     in.Name,
		SiteID:   in.SiteID,
		SourceTs: in.Timestamp * microsPerMilli,
		SensorID: in.SensorID,
	}

	err = setValue(&out, &in)
	if err != nil {
		return in, nil, err
	}

	data, err := json.Marshal(out)
	if err != nil {
		return in, nil, fmt.Errorf("encode: %w", err)
	}

	return in, data, nil
}

func validate(in *inputRecord) error {
	switch {
	case in.Name == "":
		return fmt.Errorf("%w: %w name", errQuality, errMissingField)
	case in.SiteID == "":
		return fmt.Errorf("%w: %w site_id", errQuality, errMissingField)
	case in.SensorID == "":
		return fmt.Errorf("%w: %w sensor_id", errQuality, errMissingField)
	case in.Timestamp == 0:
		return fmt.Errorf("%w: %w timestamp", errQuality, errMissingField)
	default:
		return nil
	}
}

// setValue routes value into the column matching data_type. String
// representations of numbers and booleans are accepted; wrong types are not.
func setValue(out *outputRecord, in *inputRecord) error {
	if in.Value == nil {
		return nil
	}

	switch in.DataType {
	case dataTypeFloat:
		return setFloat(out, in.Value)
	case dataTypeBoolean:
		return setBool(out, in.Value)
	case dataTypeString:
		s := fmt.Sprint(in.Value)
		out.ValueString = &s

		return nil
	default:
		return fmt.Errorf("%w: %w: %q", errQuality, errUnknownDataType, in.DataType)
	}
}

func setFloat(out *outputRecord, v any) error {
	f, err := toFloat(v)
	if err != nil {
		return fmt.Errorf("%w: %w", errQuality, err)
	}

	out.ValueDouble = &f

	return nil
}

func setBool(out *outputRecord, v any) error {
	b, err := toBool(v)
	if err != nil {
		return fmt.Errorf("%w: %w", errQuality, err)
	}

	out.ValueBoolean = &b

	return nil
}

func toFloat(v any) (float64, error) {
	switch x := v.(type) {
	case float64:
		return x, nil
	case string:
		f, err := strconv.ParseFloat(strings.TrimSpace(x), floatBitSize)
		if err != nil {
			return 0, fmt.Errorf("%w: %q", errNotFloat, x)
		}

		return f, nil
	default:
		return 0, fmt.Errorf("%w: %w %T", errNotFloat, errUnsupportedType, v)
	}
}

func toBool(v any) (bool, error) {
	switch x := v.(type) {
	case bool:
		return x, nil
	case string:
		return parseBoolString(x)
	default:
		return false, fmt.Errorf("%w: %w %T", errNotBoolean, errUnsupportedType, v)
	}
}

func parseBoolString(s string) (bool, error) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "true", "1", "yes":
		return true, nil
	case "false", "0", "no":
		return false, nil
	default:
		return false, fmt.Errorf("%w: %q", errNotBoolean, s)
	}
}

func truncate(b []byte, n int) string {
	if len(b) <= n {
		return string(b)
	}

	return string(b[:n]) + "...[truncated]"
}
