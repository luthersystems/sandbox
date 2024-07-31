package oracle

import (
	"context"

	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc/metadata"
)

const (
	profilingHeader = "x-profile-request"
)

type headerControlSampler struct{}

func (ts headerControlSampler) ShouldSample(p sdktrace.SamplingParameters) sdktrace.SamplingResult {
	psc := trace.SpanContextFromContext(p.ParentContext)
	if headerSet(p.ParentContext) {
		return sdktrace.SamplingResult{
			Decision:   sdktrace.RecordAndSample,
			Tracestate: psc.TraceState(),
		}
	}
	return sdktrace.SamplingResult{
		Decision:   sdktrace.Drop,
		Tracestate: psc.TraceState(),
	}
}

func (ts headerControlSampler) Description() string {
	return "HeaderControlSampler"
}

func HeaderControlSampler() sdktrace.Sampler {
	return &headerControlSampler{}
}

func headerSet(ctx context.Context) bool {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return false
	}
	headers := md.Get(profilingHeader)
	if len(headers) == 0 {
		return false
	}
	return headers[0] == "1"
}
