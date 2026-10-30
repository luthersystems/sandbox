// Copyright © 2021 Luther Systems, Ltd. All right reserved.

// Helpers for oracle tests.

package oracle

import (
	"context"
	"strings"
	"testing"

	common "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/common/v1"
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
		t.Cleanup(stop)
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

func testDetails() *pb.CreateClaimRequest {
	return &pb.CreateClaimRequest{
		DateOfAccident: "2024-01-15",
		DamageAmount:   500000,
		ClaimReason:    "Car accident due to adverse weather conditions.",
	}
}

func testClaimant() *pb.Claimant {
	return &pb.Claimant{
		Dob:             "1945-11-01",
		Surname:         "Smith",
		Forename:        "Raymond",
		FullAddress:     "3 High Street",
		AddressNumber:   "3",
		AddressStreet1:  "High Street",
		AddressPostcode: "BA13 3BN",
		AddressPostTown: "Westbury",
		Nationality:     pb.Nationality_NATIONALITY_GB,
	}
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
	t.Cleanup(stop)
	ctx := context.Background()
	resp, err := server.GetHealthCheck(ctx, &healthcheck.GetHealthCheckRequest{})
	require.NoError(t, err)
	require.Equal(t, 2, len(resp.GetReports()))
	// The phylum defines no healthcheck endpoint. The router's endpoint
	// reports the service name that main.lisp gives router:set-service-info.
	var found bool
	for _, r := range resp.GetReports() {
		if r.GetServiceName() == "sandbox" {
			found = true
			assert.Equal(t, "UP", r.GetStatus())
			assert.NotEmpty(t, r.GetServiceVersion())
		}
	}
	assert.True(t, found, "no report from the sandbox phylum: %v", resp.GetReports())
}

func TestGetClaim(t *testing.T) {
	server, stop := makeTestServer(t)
	t.Cleanup(stop)
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

// TestClaimFlow drives the claim flow through the oracle: a new claim waits
// for its claimant, keeps the details it was created with, and moves to the
// first connector step when the claimant arrives.
func TestClaimFlow(t *testing.T) {
	server, stop := makeTestServer(t)
	t.Cleanup(stop)
	ctx := context.Background()

	created, err := server.CreateClaim(ctx, testDetails())
	require.NoError(t, err)
	require.Nil(t, created.GetException())
	claim := created.GetClaim()
	require.NotEmpty(t, claim.GetClaimId())
	assert.Equal(t, pb.ClaimState_CLAIM_STATE_WAITING, claim.GetState())
	assert.Equal(t, "claimant", claim.GetStep())
	assert.Equal(t, testDetails().GetClaimReason(), claim.GetClaimReason())

	got, err := server.GetClaim(ctx, &pb.GetClaimRequest{ClaimId: claim.GetClaimId()})
	require.NoError(t, err)
	require.Nil(t, got.GetException())
	assert.Equal(t, "claimant", got.GetClaim().GetStep())
	assert.Equal(t, claim.GetGen(), got.GetClaim().GetGen())
	assert.Equal(t, testDetails().GetDamageAmount(), got.GetClaim().GetDamageAmount())
	assert.Equal(t, testDetails().GetDateOfAccident(), got.GetClaim().GetDateOfAccident())

	added, err := server.AddClaimant(ctx, &pb.AddClaimantRequest{
		ClaimId:  claim.GetClaimId(),
		Claimant: testClaimant(),
		Gen:      claim.GetGen(),
	})
	require.NoError(t, err)
	require.Nil(t, added.GetException())
	after := added.GetClaim()
	assert.Equal(t, pb.ClaimState_CLAIM_STATE_WAITING, after.GetState())
	assert.Equal(t, "verify-identity", after.GetStep())
	assert.Greater(t, after.GetGen(), claim.GetGen())
	assert.Equal(t, "Raymond", after.GetClaimant().GetForename())
	assert.Equal(t, pb.Nationality_NATIONALITY_GB, after.GetClaimant().GetNationality())
	assert.Equal(t, testDetails().GetClaimReason(), after.GetClaimReason())
}

// TestCreateClaimRequestKey checks that a retried create with the same
// request key returns the first claim, not a second one.
func TestCreateClaimRequestKey(t *testing.T) {
	server, stop := makeTestServer(t)
	t.Cleanup(stop)
	ctx := context.Background()
	req := testDetails()
	req.RequestKey = "create-1"
	first, err := server.CreateClaim(ctx, req)
	require.NoError(t, err)
	require.Nil(t, first.GetException())
	again, err := server.CreateClaim(ctx, req)
	require.NoError(t, err)
	require.Nil(t, again.GetException())
	assert.Equal(t, first.GetClaim().GetClaimId(), again.GetClaim().GetClaimId())
}

// TestAddClaimantRefusals checks that the flow's refusals reach the client
// as exceptions and change nothing.
func TestAddClaimantRefusals(t *testing.T) {
	server, stop := makeTestServer(t)
	t.Cleanup(stop)
	ctx := context.Background()
	created, err := server.CreateClaim(ctx, testDetails())
	require.NoError(t, err)
	claim := created.GetClaim()

	noName := testClaimant()
	noName.Forename = ""
	// code is the flow's refusal code, which the exception text starts with.
	tests := []struct {
		name string
		req  *pb.AddClaimantRequest
		code string
	}{
		{"missing forename", &pb.AddClaimantRequest{ClaimId: claim.GetClaimId(), Claimant: noName, Gen: claim.GetGen()}, "schema"},
		{"stale gen", &pb.AddClaimantRequest{ClaimId: claim.GetClaimId(), Claimant: testClaimant(), Gen: claim.GetGen() + 1}, "stale-generation"},
		{"unknown claim", &pb.AddClaimantRequest{ClaimId: "xyz", Claimant: testClaimant(), Gen: claim.GetGen()}, "not-found"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resp, err := server.AddClaimant(ctx, tc.req)
			require.NoError(t, err)
			require.NotNil(t, resp.GetException())
			assert.Equal(t, common.Exception_BUSINESS, resp.GetException().GetType())
			assert.True(t, strings.HasPrefix(resp.GetException().GetDescription(), tc.code+":"),
				"exception %q should start with %q", resp.GetException().GetDescription(), tc.code)
		})
	}
	got, err := server.GetClaim(ctx, &pb.GetClaimRequest{ClaimId: claim.GetClaimId()})
	require.NoError(t, err)
	assert.Equal(t, "claimant", got.GetClaim().GetStep())
	assert.Equal(t, claim.GetGen(), got.GetClaim().GetGen())
}
