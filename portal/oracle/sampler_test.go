// Copyright © 2026 Luther Systems, Ltd. All right reserved.

package oracle

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc/metadata"
)

func TestProfileSampler(t *testing.T) {
	withHeader := func(v string) context.Context {
		return metadata.NewIncomingContext(context.Background(), metadata.Pairs(ProfileRequestHeader, v))
	}
	sampledParent := trace.ContextWithSpanContext(context.Background(), trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    trace.TraceID{1},
		SpanID:     trace.SpanID{1},
		TraceFlags: trace.FlagsSampled,
	}))
	unsampledParent := trace.ContextWithSpanContext(withHeader("1"), trace.NewSpanContext(trace.SpanContextConfig{
		TraceID: trace.TraceID{2},
		SpanID:  trace.SpanID{2},
	}))
	for _, tc := range []struct {
		name string
		ctx  context.Context
		want sdktrace.SamplingDecision
	}{
		{"no header", context.Background(), sdktrace.Drop},
		{"header 1", withHeader("1"), sdktrace.RecordAndSample},
		{"header 0", withHeader("0"), sdktrace.Drop},
		{"header empty", withHeader(""), sdktrace.Drop},
		// A child follows its parent, header or not.
		{"sampled parent", sampledParent, sdktrace.RecordAndSample},
		{"unsampled parent with header", unsampledParent, sdktrace.Drop},
	} {
		t.Run(tc.name, func(t *testing.T) {
			res := ProfileSampler().ShouldSample(sdktrace.SamplingParameters{
				ParentContext: tc.ctx,
				TraceID:       trace.TraceID{3},
				Name:          "span",
			})
			assert.Equal(t, tc.want, res.Decision)
		})
	}
}
