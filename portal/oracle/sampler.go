// Copyright © 2026 Luther Systems, Ltd. All right reserved.

package oracle

import (
	"context"

	"github.com/luthersystems/svc/opttrace"
	"github.com/luthersystems/svc/oracle"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc/metadata"
)

// ProfileRequestHeader is the request header that asks the oracle to trace
// one request: "x-profile-request: 1". The Martin tests send it, so with
// tracing on (make up TRACING=1) every test request is traced, and other
// traffic, such as health probes, is not.
//
// The gateway and the chaincode sample a span only when its parent was
// sampled (ParentBased(NeverSample) in substrate), so the oracle's decision
// for the request is the decision for the whole trace.
const ProfileRequestHeader = "x-profile-request"

// ProfileSampler samples a new trace when its request carries
// ProfileRequestHeader with the value "1", and otherwise drops it. A span
// with a parent follows the parent's decision, so every span of a profiled
// request is kept. (The oracle's gateway does not forward a caller's
// traceparent header, so each request starts a new trace here.)
//
// The oracle forwards the header from HTTP to gRPC metadata only when it is
// in Config.ForwardedHeaders; see ConfigureProfileSampling.
//
// Any client can send the header. That is what a local network wants. An
// oracle that untrusted clients can reach, with an OTLP endpoint, should
// have its ingress remove the header, or the clients choose how much it
// traces.
func ProfileSampler() sdktrace.Sampler {
	return sdktrace.ParentBased(profileRootSampler{})
}

type profileRootSampler struct{}

func (profileRootSampler) ShouldSample(p sdktrace.SamplingParameters) sdktrace.SamplingResult {
	decision := sdktrace.Drop
	if profileRequested(p.ParentContext) {
		decision = sdktrace.RecordAndSample
	}
	return sdktrace.SamplingResult{
		Decision:   decision,
		Tracestate: trace.SpanContextFromContext(p.ParentContext).TraceState(),
	}
}

func (profileRootSampler) Description() string {
	return "ProfileRequestSampler"
}

func profileRequested(ctx context.Context) bool {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return false
	}
	v := md.Get(ProfileRequestHeader)
	return len(v) > 0 && v[0] == "1"
}

// ConfigureProfileSampling makes the oracle trace only profiled requests: it
// forwards ProfileRequestHeader to the gRPC handlers, where ProfileSampler
// reads it, and sets ProfileSampler as the tracer's sampler. Without a
// sampler the oracle would trace every request once an OTLP endpoint is
// set, including the health probes that run every few seconds.
// SANDBOX_ORACLE_TRACE_ALL=true (portal/start.go) skips it, for a collector
// that should get every request.
func ConfigureProfileSampling(cfg *oracle.Config) {
	cfg.ForwardedHeaders = append(cfg.ForwardedHeaders, ProfileRequestHeader)
	cfg.TraceOpts = append(cfg.TraceOpts, opttrace.WithSampler(ProfileSampler()))
}
