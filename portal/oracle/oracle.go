// Copyright © 2024 Luther Systems, Ltd. All right reserved.

// Package oracle implements the sandbox UI portal.
package oracle

import (
	"context"
	"fmt"

	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	srv "github.com/luthersystems/sandbox/api/srvpb/v1"
	"github.com/luthersystems/svc/oracle"
	"google.golang.org/grpc"
)

// Config configures the portal.
type Config struct {
	oracle.Config
}

type portal struct {
	srv.UnimplementedSandboxServiceServer
	orc *oracle.Oracle
}

func (p *portal) RegisterServiceServer(grpcServer *grpc.Server) {
	srv.RegisterSandboxServiceServer(grpcServer, p)
}

func (p *portal) RegisterServiceClient(ctx context.Context, grpcConn *grpc.ClientConn, mux *runtime.ServeMux) error {
	return srv.RegisterSandboxServiceHandlerClient(ctx, mux, srv.NewSandboxServiceClient(grpcConn))
}

// Run starts an oracle and blocks the caller until it completes.
func Run(ctx context.Context, config *Config) error {
	if orc, err := oracle.NewOracle(&config.Config); err != nil {
		return fmt.Errorf("new oracle: %w", err)
	} else {
		return orc.StartGateway(ctx, &portal{orc: orc})
	}
}
