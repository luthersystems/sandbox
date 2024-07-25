// Copyright © 2021 Luther Systems, Ltd. All right reserved.

// Helpers for oracle tests.

package oracle

import (
	"context"
	"testing"

	healthcheck "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/healthcheck/v1"
	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/svc/oracle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func makeTestServerFrom(t *testing.T, bytes []byte) (*portal, func()) {
	t.Helper()
	orc, stop := oracle.NewTestOracleFrom(t, bytes)
	return &portal{orc: orc}, stop
}

func makeTestServer(t *testing.T) (*portal, func()) {
	t.Helper()
	return makeTestServerFrom(t, nil)
}

func TestSnapshot(t *testing.T) {
	server, stop := makeTestServer(t)
	// Take a snapshot of the current server state, then shut it down
	snap := server.orc.Snapshot(t)
	stop()

	// Start a new oracle, restoring state from the snapshot (twice)
	for i := 0; i < 2; i++ {
		server, stop = makeTestServerFrom(t, snap)
		defer stop()
		req := &healthcheck.GetHealthCheckRequest{}
		ctx := context.Background()
		resp, err := server.GetHealthCheck(ctx, req)
		require.NoError(t, err)
		require.Nil(t, resp.GetException())
	}
}

func createAccount(t *testing.T, server *portal, id string, balance int64) bool {
	t.Helper()
	resp, err := server.CreateAccount(context.Background(), &pb.CreateAccountRequest{
		Account: &pb.Account{
			AccountId: id,
			Balance:   balance,
		},
	})
	return assert.Nil(t, err) && assert.NotNil(t, resp)
}

func getAccount(t *testing.T, server *portal, id string, dst **pb.Account) bool {
	t.Helper()
	resp, err := server.GetAccount(context.Background(), &pb.GetAccountRequest{
		AccountId: id,
	})
	*dst = resp.GetAccount()
	return assert.Nil(t, err) && assert.NotNil(t, resp) && assert.Nil(t, resp.GetException())
}

func TestHealthCheck(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	ctx := context.Background()
	resp, err := server.GetHealthCheck(ctx, &healthcheck.GetHealthCheckRequest{})
	require.NoError(t, err)
	require.Equal(t, 2, len(resp.GetReports()))
}

func TestCreateAccount(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	if createAccount(t, server, "abc", 100) {
		ctx := context.Background()
		resp, err := server.CreateAccount(ctx, &pb.CreateAccountRequest{
			Account: &pb.Account{
				AccountId: "abc",
				Balance:   100,
			},
		})
		if assert.Nil(t, err) {
			if assert.NotNil(t, resp) {
				assert.NotNil(t, resp.Exception)
			}
		}
	}
}

func TestGetAccount(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	if !createAccount(t, server, "abc", 100) {
		return
	}
	var acct *pb.Account
	if getAccount(t, server, "abc", &acct) {
		assert.Equal(t, int64(100), acct.GetBalance())

		resp, err := server.GetAccount(context.Background(), &pb.GetAccountRequest{
			AccountId: "xyz",
		})
		if assert.NoError(t, err) {
			if assert.NotNil(t, resp) {
				assert.NotNil(t, resp.Exception)
			}
		}
	}
}

func TestTransfer(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	if !createAccount(t, server, "abc", 100) {
		return
	}
	if !createAccount(t, server, "xyz", 50) {
		return
	}
	ctx := context.Background()
	resp, err := server.Transfer(ctx, &pb.TransferRequest{
		PayerId:        "abc",
		PayeeId:        "xyz",
		TransferAmount: 30,
	})
	if assert.NoError(t, err) {
		if assert.NotNil(t, resp) {
			if assert.Nil(t, resp.Exception) {
				var acct *pb.Account
				if getAccount(t, server, "abc", &acct) {
					assert.Equal(t, int64(70), acct.Balance)
				}
				if getAccount(t, server, "xyz", &acct) {
					assert.Equal(t, int64(80), acct.Balance)
				}
			}
		}
	}

	resp, err = server.Transfer(ctx, &pb.TransferRequest{
		PayerId:        "abc",
		PayeeId:        "www",
		TransferAmount: 30,
	})
	if assert.NoError(t, err) {
		if assert.NotNil(t, resp) {
			assert.NotNil(t, resp.Exception)
		}
	}

	resp, err = server.Transfer(ctx, &pb.TransferRequest{
		PayerId:        "www",
		PayeeId:        "xyz",
		TransferAmount: 30,
	})
	if assert.NoError(t, err) {
		if assert.NotNil(t, resp) {
			assert.NotNil(t, resp.Exception)
		}
	}
}
