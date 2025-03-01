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

// phylumRelPath is the path to the phylum dir relative to this file.
const phylumRelPath = "../../phylum"

func makeTestServerFrom(t *testing.T, b []byte) (*portal, func()) {
	t.Helper()
	cfg := &Config{Config: *oracle.DefaultConfig()}
	cfg.PhylumPath = phylumRelPath
	orc, stop := oracle.NewTestOracle(t, &cfg.Config, oracle.WithSnapshot(b))
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

func createClaim(t *testing.T, server *portal, id *string) bool {
	t.Helper()
	resp, err := server.CreateClaim(context.Background(), &pb.CreateClaimRequest{})
	*id = resp.GetClaim().GetClaimId()
	return assert.Nil(t, err) && assert.NotNil(t, resp)
}

func getClaim(t *testing.T, server *portal, id string, dst **pb.Claim) bool {
	t.Helper()
	resp, err := server.GetClaim(context.Background(), &pb.GetClaimRequest{
		ClaimId: id,
	})
	*dst = resp.GetClaim()
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

func TestGetAccount(t *testing.T) {
	server, stop := makeTestServer(t)
	defer stop()
	var id string
	if !createClaim(t, server, &id) {
		return
	}
	var claim *pb.Claim
	if getClaim(t, server, id, &claim) {
		resp, err := server.GetClaim(context.Background(), &pb.GetClaimRequest{
			ClaimId: "xyz",
		})
		if assert.NoError(t, err) {
			if assert.NotNil(t, resp) {
				assert.NotNil(t, resp.GetException())
			}
		}
	}
}
