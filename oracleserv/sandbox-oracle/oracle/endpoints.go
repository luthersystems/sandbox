package oracle

import (
	"context"

	healthcheck "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/healthcheck/v1"
	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/oracle/oracle"
)

// GetHealthCheck returns health status.
func (p *portal) GetHealthCheck(ctx context.Context, req *healthcheck.GetHealthCheckRequest) (*healthcheck.GetHealthCheckResponse, error) {
	return p.orc.GetHealthCheck(ctx, req)
}

// CreateAccount is an example resource creation endpoint.
func (p *portal) CreateAccount(ctx context.Context, req *pb.CreateAccountRequest) (*pb.CreateAccountResponse, error) {
	return oracle.Call(p.orc, ctx, "create_account", req, &pb.CreateAccountResponse{})
}

// UpdateAccount is an example resource update endpoint.
func (p *portal) UpdateAccount(ctx context.Context, req *pb.UpdateAccountRequest) (*pb.UpdateAccountResponse, error) {
	return oracle.Call(p.orc, ctx, "update_account", req, &pb.UpdateAccountResponse{})
}

// GetAccount is an example query endpoint.
func (p *portal) GetAccount(ctx context.Context, req *pb.GetAccountRequest) (*pb.GetAccountResponse, error) {
	return oracle.Call(p.orc, ctx, "get_account", req, &pb.GetAccountResponse{})
}

// GetUserAccounts is an example query endpoint.
func (p *portal) GetUserAccounts(ctx context.Context, req *pb.GetUserAccountsRequest) (*pb.GetUserAccountsResponse, error) {
	return oracle.Call(p.orc, ctx, "get_user_accounts", req, &pb.GetUserAccountsResponse{})
}

// DeleteAccount is an example resource deletion endpoint.
func (p *portal) DeleteAccount(ctx context.Context, req *pb.DeleteAccountRequest) (*pb.DeleteAccountResponse, error) {
	return oracle.Call(p.orc, ctx, "delete_account", req, &pb.DeleteAccountResponse{})
}

// Transfer is an example write operation.
func (p *portal) Transfer(ctx context.Context, req *pb.TransferRequest) (*pb.TransferResponse, error) {
	return oracle.Call(p.orc, ctx, "transfer", req, &pb.TransferResponse{})
}
