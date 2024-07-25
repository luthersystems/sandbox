// Copyright © 2021 Luther Systems, Ltd. All right reserved.

// Package oracle implements the sandbox UI portal.
package oracle

import (
	"context"
	"fmt"

	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"github.com/luthersystems/sandbox/api"
	srv "github.com/luthersystems/sandbox/api/srvpb/v1"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/version"
	"github.com/luthersystems/svc/oracle"
	"google.golang.org/grpc"
)

var swaggerHandler = api.SwaggerHandlerOrPanic("v1/oracle")

type portal struct {
	srv.UnimplementedLedgerServiceServer

	orc *oracle.Oracle
}

func (p *portal) RegisterServiceServer(grpcServer *grpc.Server) {
	srv.RegisterLedgerServiceServer(grpcServer, p)
}

func (p *portal) RegisterServiceClient(ctx context.Context, grpcConn *grpc.ClientConn, mux *runtime.ServeMux) error {
	return srv.RegisterLedgerServiceHandlerClient(ctx, mux, srv.NewLedgerServiceClient(grpcConn))
}

// Run starts an oracle and blocks the caller until it completes.
func Run(config *oracle.Config) error {
	config.SetSwaggerHandler(swaggerHandler)
	config.PhylumServiceName = "sandbox-cc"
	config.ServiceName = "sandbox-oracle"
	config.Version = version.Version
	config.GatewayEndpoint = "http://shiroclient_gw_sandbox:8082"

	orc, err := oracle.NewOracle(config)
	if err != nil {
		return fmt.Errorf("new oracle: %w", err)
	}

	return orc.Run(&portal{orc: orc})
}
