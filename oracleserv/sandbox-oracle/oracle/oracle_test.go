// Copyright © 2021 Luther Systems, Ltd. All right reserved.

// Helpers for oracle tests.

package oracle

import (
	"bytes"
	"context"
	"io"
	"testing"

	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type testWriter struct {
	t *testing.T
	b *bytes.Buffer
}

func newTestWriter(t *testing.T) *testWriter {
	var b bytes.Buffer
	return &testWriter{t: t, b: &b}
}

func (tw testWriter) Write(p []byte) (n int, err error) {
	for _, b := range p {
		if b == '\n' {
			tw.t.Log(tw.b.String())
			tw.b.Reset()
			continue
		}
		// bytes.Buffer panics on error
		tw.b.WriteByte(b)
	}
	return n, nil
}

func makeTestServer(t *testing.T, opts ...Option) (*Oracle, func()) {
	t.Parallel()
	t.Helper()
	return newTestOracle(t, opts...)
}

func newTestOracle(t *testing.T, opts ...Option) (*Oracle, func()) {
	return newTestOracleFrom(t, nil, opts...)
}

func newTestOracleFrom(t *testing.T, snapshot []byte, opts ...Option) (*Oracle, func()) {
	cfg := DefaultConfig()
	cfg.Verbose = testing.Verbose()
	logger := logrus.New()
	logger.SetOutput(newTestWriter(t))
	var r io.Reader
	if snapshot != nil {
		r = bytes.NewReader(snapshot)
	}
	finalOpts := []Option{
		WithLogBase(logger.WithFields(nil)),
		WithMockPhylumFrom("../../../phylum", r),
	}
	finalOpts = append(finalOpts, opts...)
	server, err := New(cfg, finalOpts...)
	if err != nil {
		t.Fatal(err)
	}

	if cfg.Verbose {
		logger.SetLevel(logrus.DebugLevel)
	}

	orcStop := func() {
		err := server.Close()
		require.NoError(t, err)
	}

	return server, orcStop
}

func snapshotServer(t *testing.T, oracle *Oracle) []byte {
	var snapshot bytes.Buffer
	err := oracle.phylum.MockSnapshot(&snapshot)
	require.NoError(t, err)
	return snapshot.Bytes()
}

func TestSnapshot(t *testing.T) {
	server, stop := makeTestServer(t)
	// Take a snapshot of the current server state, then shut it down
	snap := snapshotServer(t, server)
	stop()

	// Start a new oracle, restoring state from the snapshot (twice)
	for i := 0; i < 2; i++ {
		server, stop = newTestOracleFrom(t, snap)
		defer stop()
		req := &pb.HealthCheckRequest{}
		ctx := context.Background()
		resp, err := server.HealthCheck(ctx, req)
		require.NoError(t, err)
		require.Nil(t, resp.GetException())
	}
}

func createAccount(t *testing.T, server *Oracle, id string, balance int64) bool {
	t.Helper()
	resp, err := server.CreateAccount(context.Background(), &pb.CreateAccountRequest{
		Account: &pb.Account{
			AccountId:      id,
			CurrentBalance: balance,
		},
	})
	return assert.Nil(t, err) && assert.NotNil(t, resp) && assert.Nil(t, resp.Exception)
}

func getAccount(t *testing.T, server *Oracle, id string, dst **pb.Account) bool {
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
	resp, err := server.HealthCheck(ctx, &pb.HealthCheckRequest{})
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
				AccountId:      "abc",
				CurrentBalance: 100,
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
		assert.Equal(t, int64(100), acct.GetCurrentBalance())

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
					assert.Equal(t, int64(70), acct.CurrentBalance)
				}
				if getAccount(t, server, "xyz", &acct) {
					assert.Equal(t, int64(80), acct.CurrentBalance)
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

func createClient(t *testing.T, server *Oracle, id string, iban string) bool {
	t.Helper()
	resp, err := server.CreateClient(context.Background(), &pb.CreateClientRequest{
		Client: &pb.Client{
			ClientId: id,
			Iban:     iban,
		},
	})
	return assert.Nil(t, err) && assert.NotNil(t, resp) && assert.Nil(t, resp.Exception)
}

func TestCreateClient(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	if !createClient(t, server, "fnord", "eris001") {
		return
	}
}

func getClient(t *testing.T, server *Oracle, id string) bool {
	t.Helper()
	resp, err := server.GetClient(context.Background(), &pb.GetClientRequest{
		ClientId: id,
	})

	return assert.Nil(t, err) && assert.NotNil(t, resp) && assert.Nil(t, resp.Exception)
}

func TestGetClient(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	if !getClient(t, server, "fnord") {
		return
	}
}
