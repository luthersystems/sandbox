// Copyright © 2024 Luther Systems, Ltd. All right reserved.
package main

import (
	"github.com/luthersystems/sandbox/api"
	"github.com/luthersystems/sandbox/portal/oracle"
	"github.com/luthersystems/sandbox/portal/version"
	svc "github.com/luthersystems/svc/oracle"
)

type startCmd struct {
	baseCmd
	ListenAddress   string `short:"l" help:"Address to listen on" default:":8080" env:"SANDBOX_ORACLE_LISTEN_ADDRESS"`
	GatewayEndpoint string `short:"g" help:"URL for shiroclient gateway" env:"SANDBOX_ORACLE_GATEWAY_ENDPOINT"`
	OTLPEndpoint    string `short:"o" help:"URL for OTLP provider" env:"SANDBOX_ORACLE_OTLP_ENDPOINT"`
	PhylumPath      string `short:"p" help:"Phylum path for in-memory mode" default:"./phylum" env:"SANDBOX_ORACLE_PHYLUM_PATH"`
	Verbose         bool   `short:"v" help:"Verbose logging" default:"false" env:"SANDBOX_ORACLE_VERBOSE"`
	EmulateCC       bool   `short:"e" help:"Enable in-memory-mode" default:"false" env:"SANDBOX_ORACLE_EMULATE_CC"`
}

func (r *startCmd) Run() error {
	cfg := svc.DefaultConfig()
	cfg.PhylumServiceName = "sandbox"
	cfg.ServiceName = "sandbox-oracle"
	cfg.Version = version.Version
	cfg.PhylumPath = r.PhylumPath
	cfg.SetOTLPEndpoint(r.OTLPEndpoint)
	cfg.SetSwaggerHandler(api.SwaggerHandlerOrPanic("v1/oracle"))
	cfg.ListenAddress = r.ListenAddress
	cfg.GatewayEndpoint = r.GatewayEndpoint
	cfg.Verbose = r.Verbose
	cfg.EmulateCC = r.EmulateCC

	return oracle.Run(r.ctx, &oracle.Config{
		Config: *cfg,
	})
}
