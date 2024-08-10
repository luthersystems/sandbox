package oracle

import (
	"context"

	healthcheck "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/healthcheck/v1"
	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/svc/oracle"
)

// GetHealthCheck returns health status.
func (p *portal) GetHealthCheck(ctx context.Context, req *healthcheck.GetHealthCheckRequest) (*healthcheck.GetHealthCheckResponse, error) {
	return p.orc.GetHealthCheck(ctx, req)
}

// CreateAccount is an example resource creation endpoint.
func (p *portal) CreateClaim(ctx context.Context, req *pb.CreateClaimRequest) (*pb.CreateClaimResponse, error) {
	return oracle.Call(p.orc, ctx, "create_claim", req, &pb.CreateClaimResponse{})
}

// GetClaim is an example query endpoint.
func (p *portal) GetClaim(ctx context.Context, req *pb.GetClaimRequest) (*pb.GetClaimResponse, error) {
	return oracle.Call(p.orc, ctx, "get_claim", req, &pb.GetClaimResponse{})
}
