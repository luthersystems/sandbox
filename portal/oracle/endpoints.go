package oracle

import (
	"context"
	"fmt"

	healthcheck "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/healthcheck/v1"
	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/private"
	"github.com/luthersystems/svc/opttrace"
	"github.com/luthersystems/svc/oracle"
)

func (p *portal) defaultConfigs(_ context.Context) []shiroclient.Config {
	cfg, err := private.WithSeed()
	if err != nil {
		panic(err)
	}
	return []shiroclient.Config{cfg}
}

// GetHealthCheck returns health status.
func (p *portal) GetHealthCheck(ctx context.Context, req *healthcheck.GetHealthCheckRequest) (*healthcheck.GetHealthCheckResponse, error) {
	return p.orc.GetHealthCheck(ctx, req)
}

// CreateClaim is an example resource creation endpoint.
func (p *portal) CreateClaim(ctx context.Context, req *pb.CreateClaimRequest) (*pb.CreateClaimResponse, error) {
	// Example trace without elps filtering (includes all spans)
	ctx, span := p.orc.TraceContext(ctx, "CreateClaim")
	defer span()
	ctx, err := opttrace.TraceContextWithoutELPSFilter(ctx)
	if err != nil {
		return nil, fmt.Errorf("trace context: %w", err)
	}
	return oracle.Call(p.orc, ctx, "create_claim", req, &pb.CreateClaimResponse{}, p.defaultConfigs(ctx)...)
}

// AddClaimant is an example resource update endpoint.
func (p *portal) AddClaimant(ctx context.Context, req *pb.AddClaimantRequest) (*pb.AddClaimantResponse, error) {
	// Normal tracing enabled, WITH elps filtering.
	return oracle.Call(p.orc, ctx, "add_claimant", req, &pb.AddClaimantResponse{}, p.defaultConfigs(ctx)...)
}

// GetClaim is an example query endpoint.
func (p *portal) GetClaim(ctx context.Context, req *pb.GetClaimRequest) (*pb.GetClaimResponse, error) {
	return oracle.Call(p.orc, ctx, "get_claim", req, &pb.GetClaimResponse{})
}
