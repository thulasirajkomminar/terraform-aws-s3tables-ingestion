package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

const (
	keyName      = "name"
	keyDataType  = "data_type"
	keySiteID    = "site_id"
	keySensorID  = "sensor_id"
	keyTimestamp = "timestamp"
	keyValue     = "value"

	wantDecode      = "decode"
	wantNotFloat    = "value not a float"
	wantNotBoolean  = "value not a boolean"
	wantUnknownType = "unknown data_type"
)

func testNow() time.Time {
	return time.Date(2026, 6, 11, 12, 0, 0, 0, time.UTC)
}

// validPayload builds a well-formed record. An override with a nil value
// removes the key entirely; use json.RawMessage("null") for an explicit null.
func validPayload(t *testing.T, overrides map[string]any) []byte {
	t.Helper()

	record := map[string]any{
		keyName:      "temperature",
		keyDataType:  dataTypeFloat,
		keySiteID:    "site-01",
		keySensorID:  "sensor-a1",
		keyTimestamp: int64(1718100000000), // 2024-06-11T10:00:00.000Z
		keyValue:     21.5,
	}

	for k, v := range overrides {
		if v == nil {
			delete(record, k)

			continue
		}

		record[k] = v
	}

	data, err := json.Marshal(record)
	require.NoError(t, err)

	return data
}

func decodeOutput(t *testing.T, data []byte) outputRecord {
	t.Helper()

	var out outputRecord

	require.NoError(t, json.Unmarshal(data, &out))

	return out
}

func TestTransformValidRecords(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		overrides map[string]any
		check     func(t *testing.T, out outputRecord)
	}{
		{
			name: "float from JSON number",
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueDouble)
				assert.InDelta(t, 21.5, *out.ValueDouble, 0)
				assert.Nil(t, out.ValueBoolean)
				assert.Nil(t, out.ValueString)
			},
		},
		{
			name:      "float from string",
			overrides: map[string]any{keyValue: "21.5"},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueDouble)
				assert.InDelta(t, 21.5, *out.ValueDouble, 0)
			},
		},
		{
			name:      "float from string with whitespace",
			overrides: map[string]any{keyValue: " 21.5 "},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueDouble)
				assert.InDelta(t, 21.5, *out.ValueDouble, 0)
			},
		},
		{
			name:      "float from integer JSON number",
			overrides: map[string]any{keyValue: 42},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueDouble)
				assert.InDelta(t, 42.0, *out.ValueDouble, 0)
			},
		},
		{
			name:      "boolean from bool",
			overrides: map[string]any{keyDataType: dataTypeBoolean, keyValue: true},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueBoolean)
				assert.True(t, *out.ValueBoolean)
				assert.Nil(t, out.ValueDouble)
				assert.Nil(t, out.ValueString)
			},
		},
		{
			name:      "boolean false from bool",
			overrides: map[string]any{keyDataType: dataTypeBoolean, keyValue: false},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueBoolean)
				assert.False(t, *out.ValueBoolean)
			},
		},
		{
			name:      "string value",
			overrides: map[string]any{keyDataType: dataTypeString, keyValue: "running"},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				require.NotNil(t, out.ValueString)
				assert.Equal(t, "running", *out.ValueString)
				assert.Nil(t, out.ValueDouble)
				assert.Nil(t, out.ValueBoolean)
			},
		},
		{
			name:      "null value keeps all value columns null",
			overrides: map[string]any{keyValue: json.RawMessage("null")},
			check: func(t *testing.T, out outputRecord) {
				t.Helper()

				assert.Nil(t, out.ValueDouble)
				assert.Nil(t, out.ValueBoolean)
				assert.Nil(t, out.ValueString)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			_, data, err := transform(validPayload(t, tt.overrides), testNow())
			require.NoError(t, err)
			tt.check(t, decodeOutput(t, data))
		})
	}
}

func TestTransformFieldMapping(t *testing.T) {
	t.Parallel()

	_, data, err := transform(validPayload(t, nil), testNow())
	require.NoError(t, err)

	out := decodeOutput(t, data)

	assert.Equal(t, "temperature", out.Name)
	assert.Equal(t, "site-01", out.SiteID)
	assert.Equal(t, "sensor-a1", out.SensorID)
	assert.Equal(t, int64(1718100000000000), out.SourceTs, "millis must become micros")
	assert.Equal(t, testNow().UnixMicro(), out.IngestTs, "ingest_ts is stamped server-side")
}

func TestTransformBooleanStringVariants(t *testing.T) {
	t.Parallel()

	trueVariants := []string{"true", "TRUE", "True", "1", "yes", "YES", " true "}
	falseVariants := []string{"false", "FALSE", "False", "0", "no", "NO", " false "}

	for _, v := range trueVariants {
		t.Run("true/"+v, func(t *testing.T) {
			t.Parallel()

			_, data, err := transform(validPayload(t, map[string]any{keyDataType: dataTypeBoolean, keyValue: v}), testNow())
			require.NoError(t, err)

			out := decodeOutput(t, data)
			require.NotNil(t, out.ValueBoolean)
			assert.True(t, *out.ValueBoolean)
		})
	}

	for _, v := range falseVariants {
		t.Run("false/"+v, func(t *testing.T) {
			t.Parallel()

			_, data, err := transform(validPayload(t, map[string]any{keyDataType: dataTypeBoolean, keyValue: v}), testNow())
			require.NoError(t, err)

			out := decodeOutput(t, data)
			require.NotNil(t, out.ValueBoolean)
			assert.False(t, *out.ValueBoolean)
		})
	}
}

func TestTransformQualityErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		payload []byte
		wantMsg string
	}{
		{"invalid json", []byte(`{not json`), wantDecode},
		{"empty payload", []byte(``), wantDecode},
		{"wrong timestamp type", validPayload(t, map[string]any{keyTimestamp: "1718100000000"}), wantDecode},
		{"missing name", validPayload(t, map[string]any{keyName: nil}), "missing field name"},
		{"empty name", validPayload(t, map[string]any{keyName: ""}), "missing field name"},
		{"missing site_id", validPayload(t, map[string]any{keySiteID: nil}), "missing field site_id"},
		{"missing sensor_id", validPayload(t, map[string]any{keySensorID: nil}), "missing field sensor_id"},
		{"missing timestamp", validPayload(t, map[string]any{keyTimestamp: nil}), "missing field timestamp"},
		{"zero timestamp", validPayload(t, map[string]any{keyTimestamp: 0}), "missing field timestamp"},
		{"float from non-numeric string", validPayload(t, map[string]any{keyValue: "abc"}), wantNotFloat},
		{"float from bool", validPayload(t, map[string]any{keyValue: true}), wantNotFloat},
		{"float from object", validPayload(t, map[string]any{keyValue: map[string]any{"a": 1}}), wantNotFloat},
		{"boolean from number", validPayload(t, map[string]any{keyDataType: dataTypeBoolean, keyValue: 1}), wantNotBoolean},
		{"boolean from unknown string", validPayload(t, map[string]any{keyDataType: dataTypeBoolean, keyValue: "maybe"}), wantNotBoolean},
		{"boolean from object", validPayload(t, map[string]any{keyDataType: dataTypeBoolean, keyValue: map[string]any{"a": 1}}), wantNotBoolean},
		{"unknown data_type", validPayload(t, map[string]any{keyDataType: "int"}), wantUnknownType},
		{"empty data_type", validPayload(t, map[string]any{keyDataType: ""}), wantUnknownType},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			_, data, err := transform(tt.payload, testNow())
			require.Error(t, err)
			require.ErrorIs(t, err, errQuality, "quality errors must match errQuality so the handler drops them")
			require.ErrorContains(t, err, tt.wantMsg)
			assert.Nil(t, data)
		})
	}
}

// NaN and Inf parse as floats but cannot be JSON-encoded. That is a marshal
// failure, not a producer quality error, so it must NOT be dropped silently.
func TestTransformMarshalFailureIsNotQuality(t *testing.T) {
	t.Parallel()

	for _, v := range []string{"NaN", "Inf", "-Inf"} {
		t.Run(v, func(t *testing.T) {
			t.Parallel()

			_, _, err := transform(validPayload(t, map[string]any{keyValue: v}), testNow())
			require.Error(t, err)
			require.NotErrorIs(t, err, errQuality)
		})
	}
}

func TestToFloat(t *testing.T) {
	t.Parallel()

	f, err := toFloat(3.14)
	require.NoError(t, err)
	assert.InDelta(t, 3.14, f, 0)

	f, err = toFloat("2.5")
	require.NoError(t, err)
	assert.InDelta(t, 2.5, f, 0)

	f, err = toFloat(" -1e3\t")
	require.NoError(t, err)
	assert.InDelta(t, -1000.0, f, 0)

	_, err = toFloat("abc")
	require.ErrorIs(t, err, errNotFloat)

	_, err = toFloat(true)
	require.ErrorIs(t, err, errUnsupportedType)

	_, err = toFloat(nil)
	require.ErrorIs(t, err, errUnsupportedType)
}

func TestToBool(t *testing.T) {
	t.Parallel()

	b, err := toBool(true)
	require.NoError(t, err)
	assert.True(t, b)

	b, err = toBool(false)
	require.NoError(t, err)
	assert.False(t, b)

	_, err = toBool("maybe")
	require.ErrorIs(t, err, errNotBoolean)

	_, err = toBool(1.0)
	require.ErrorIs(t, err, errUnsupportedType)

	_, err = toBool(nil)
	require.ErrorIs(t, err, errUnsupportedType)
}

func TestTruncate(t *testing.T) {
	t.Parallel()

	assert.Equal(t, "short", truncate([]byte("short"), 10))
	assert.Equal(t, "exact", truncate([]byte("exact"), 5))
	assert.Equal(t, "long...[truncated]", truncate([]byte("longpayload"), 4))
}

func TestHandle(t *testing.T) {
	t.Parallel()

	event := events.KinesisFirehoseEvent{
		Records: []events.KinesisFirehoseEventRecord{
			{RecordID: "ok-1", Data: validPayload(t, nil)},
			{RecordID: "quality-1", Data: validPayload(t, map[string]any{keyName: nil})},
			{RecordID: "failure-1", Data: validPayload(t, map[string]any{keyValue: "NaN"})},
			{RecordID: "ok-2", Data: validPayload(t, map[string]any{keyDataType: dataTypeString, keyValue: "running"})},
		},
	}

	resp, err := newHandler(zap.NewNop()).Handle(t.Context(), &event)
	require.NoError(t, err)
	require.Len(t, resp.Records, 4)

	byID := map[string]events.KinesisFirehoseResponseRecord{}
	for _, r := range resp.Records {
		byID[r.RecordID] = r
	}

	assert.Equal(t, events.KinesisFirehoseTransformedStateOk, byID["ok-1"].Result)
	assert.Equal(t, events.KinesisFirehoseTransformedStateOk, byID["ok-2"].Result)
	assert.Equal(t, events.KinesisFirehoseTransformedStateDropped, byID["quality-1"].Result)
	assert.Equal(t, events.KinesisFirehoseTransformedStateProcessingFailed, byID["failure-1"].Result)

	assert.Empty(t, byID["quality-1"].Data)
	assert.Empty(t, byID["failure-1"].Data)

	out := decodeOutput(t, byID["ok-1"].Data)
	assert.Equal(t, "temperature", out.Name)
	require.NotNil(t, out.ValueDouble)
	assert.InDelta(t, 21.5, *out.ValueDouble, 0)
}

func TestHandleEmptyBatch(t *testing.T) {
	t.Parallel()

	resp, err := newHandler(zap.NewNop()).Handle(t.Context(), &events.KinesisFirehoseEvent{})
	require.NoError(t, err)
	assert.Empty(t, resp.Records)
}

func TestHandlePayloadTruncationInLogsDoesNotAffectOutput(t *testing.T) {
	t.Parallel()

	long := strings.Repeat("x", 1024)
	event := events.KinesisFirehoseEvent{
		Records: []events.KinesisFirehoseEventRecord{
			{RecordID: "big-1", Data: validPayload(t, map[string]any{keyDataType: dataTypeString, keyValue: long})},
		},
	}

	resp, err := newHandler(zap.NewNop()).Handle(t.Context(), &event)
	require.NoError(t, err)
	require.Len(t, resp.Records, 1)
	assert.Equal(t, events.KinesisFirehoseTransformedStateOk, resp.Records[0].Result)

	out := decodeOutput(t, resp.Records[0].Data)
	require.NotNil(t, out.ValueString)
	assert.Equal(t, long, *out.ValueString)
}
