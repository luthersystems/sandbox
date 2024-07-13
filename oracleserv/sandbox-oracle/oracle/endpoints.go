package oracle

import (
	"context"

	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/sandbox/phylum"
)

// CreateAccount is an example resource creation endpoint.
func (orc *Oracle) CreateAccount(ctx context.Context, req *pb.CreateAccountRequest) (*pb.CreateAccountResponse, error) {
	return phylum.Call(orc.phylum, ctx, "create_account", req, &pb.CreateAccountResponse{}, orc.txConfigs(ctx)...)
}

// UpdateAccount is an example resource update endpoint.
func (orc *Oracle) UpdateAccount(ctx context.Context, req *pb.UpdateAccountRequest) (*pb.UpdateAccountResponse, error) {
	return phylum.Call(orc.phylum, ctx, "update_account", req, &pb.UpdateAccountResponse{}, orc.txConfigs(ctx)...)
}

// GetAccount is an example query endpoint.
func (orc *Oracle) GetAccount(ctx context.Context, req *pb.GetAccountRequest) (*pb.GetAccountResponse, error) {
	return phylum.Call(orc.phylum, ctx, "get_account", req, &pb.GetAccountResponse{}, orc.txConfigs(ctx)...)
}

// GetUserAccounts is an example query endpoint.
func (orc *Oracle) GetUserAccounts(ctx context.Context, req *pb.GetUserAccountsRequest) (*pb.GetUserAccountsResponse, error) {
	return phylum.Call(orc.phylum, ctx, "get_user_accounts", req, &pb.GetUserAccountsResponse{}, orc.txConfigs(ctx)...)
}

// DeleteAccount is an example resource deletion endpoint.
func (orc *Oracle) DeleteAccount(ctx context.Context, req *pb.DeleteAccountRequest) (*pb.DeleteAccountResponse, error) {
	return phylum.Call(orc.phylum, ctx, "delete_account", req, &pb.DeleteAccountResponse{}, orc.txConfigs(ctx)...)
}

// Transfer is an example write operation.
func (orc *Oracle) Transfer(ctx context.Context, req *pb.TransferRequest) (*pb.TransferResponse, error) {
	return phylum.Call(orc.phylum, ctx, "transfer", req, &pb.TransferResponse{}, orc.txConfigs(ctx)...)
}
