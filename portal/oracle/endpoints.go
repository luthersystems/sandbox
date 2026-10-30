// Copyright © 2024 Luther Systems, Ltd. All right reserved.

package oracle

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	common "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/common/v1"
	healthcheck "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/healthcheck/v1"
	"github.com/google/uuid"
	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/phylum"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/private"
	"github.com/luthersystems/svc/opttrace"
	"github.com/luthersystems/svc/oracle"
	"github.com/luthersystems/svc/svcerr"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/structpb"
)

func (p *portal) defaultConfigs(_ context.Context) []shiroclient.Config {
	cfg, err := private.WithSeed()
	if err != nil {
		panic(err)
	}
	return []shiroclient.Config{cfg}
}

func (p *portal) GetHealthCheck(ctx context.Context, req *healthcheck.GetHealthCheckRequest) (*healthcheck.GetHealthCheckResponse, error) {
	return p.orc.GetHealthCheck(ctx, req)
}

// The claim endpoints call the claim flow in phylum/claim.lisp. defflow
// makes the flow's endpoints; the flow's :endpoints option names them
// create_claim, add_claimant and get_claim.

func (p *portal) CreateClaim(ctx context.Context, req *pb.CreateClaimRequest) (*pb.CreateClaimResponse, error) {
	// Example trace without elps filtering (includes all spans)
	ctx, span := p.orc.TraceContext(ctx, "CreateClaim")
	defer span()
	ctx, err := opttrace.TraceContextWithoutELPSFilter(ctx)
	if err != nil {
		p.orc.Log(ctx).WithError(err).Warn("tracing disabled")
	}
	// A flow start needs a request key: it makes a retried start return the
	// first claim. A client that sends none gets a random key, so its retry
	// makes a second claim, as the API did before the flow.
	key := req.GetRequestKey()
	if key == "" {
		key = uuid.NewString()
	}
	// The flow keeps the claim details as the client sent them, without the
	// key: the key belongs to the request, not to the claim.
	details := proto.CloneOf(req)
	details.RequestKey = ""
	params, err := flowParams(key, details)
	if err != nil {
		return nil, err
	}
	run, exc, err := p.callFlow(ctx, "create_claim", params, p.defaultConfigs(ctx)...)
	if err != nil {
		return nil, err
	}
	if exc != nil {
		return &pb.CreateClaimResponse{Result: &pb.CreateClaimResponse_Exception{Exception: exc}}, nil
	}
	// A start answers only the run's metadata. The details are the ones
	// this request sent, so the oracle fills them in without a second call.
	claim := run.claim()
	claim.DateOfAccident = details.GetDateOfAccident()
	claim.DamageAmount = details.GetDamageAmount()
	claim.ClaimReason = details.GetClaimReason()
	return &pb.CreateClaimResponse{Result: &pb.CreateClaimResponse_Claim{Claim: claim}}, nil
}

func (p *portal) AddClaimant(ctx context.Context, req *pb.AddClaimantRequest) (*pb.AddClaimantResponse, error) {
	// Normal tracing enabled, WITH elps filtering.
	params, err := flowParams(req.GetClaimId(), req.GetClaimant(), req.GetGen())
	if err != nil {
		return nil, err
	}
	if key := req.GetRequestKey(); key != "" {
		params = append(params, key)
	}
	_, exc, err := p.callFlow(ctx, "add_claimant", params, p.defaultConfigs(ctx)...)
	if err != nil {
		return nil, err
	}
	if exc != nil {
		return &pb.AddClaimantResponse{Result: &pb.AddClaimantResponse_Exception{Exception: exc}}, nil
	}
	// An input answers only the run's metadata. Read the claim back so the
	// response shows the claimant and the step the claim moved to.
	claim, exc, err := p.getClaim(ctx, req.GetClaimId())
	if err != nil {
		return nil, err
	}
	if exc != nil {
		return &pb.AddClaimantResponse{Result: &pb.AddClaimantResponse_Exception{Exception: exc}}, nil
	}
	return &pb.AddClaimantResponse{Result: &pb.AddClaimantResponse_Claim{Claim: claim}}, nil
}

func (p *portal) GetClaim(ctx context.Context, req *pb.GetClaimRequest) (*pb.GetClaimResponse, error) {
	claim, exc, err := p.getClaim(ctx, req.GetClaimId())
	if err != nil {
		return nil, err
	}
	if exc != nil {
		return &pb.GetClaimResponse{Result: &pb.GetClaimResponse_Exception{Exception: exc}}, nil
	}
	return &pb.GetClaimResponse{Result: &pb.GetClaimResponse_Claim{Claim: claim}}, nil
}

// getClaim reads a claim through the flow's get endpoint.
func (p *portal) getClaim(ctx context.Context, claimID string) (*pb.Claim, *common.Exception, error) {
	params, err := flowParams(claimID)
	if err != nil {
		return nil, nil, err
	}
	run, exc, err := p.callFlow(ctx, "get_claim", params)
	if err != nil || exc != nil {
		return nil, exc, err
	}
	return run.claim(), nil, nil
}

// callFlow calls the claim flow endpoint method with positional params.
//
// oracle.Call sends its request message as an endpoint's one parameter, the
// shape a hand-written defendpoint takes. A defflow endpoint takes
// positional parameters instead (a request key, a run ID, a generation), so
// callFlow sends an empty message and replaces the parameters with
// shiroclient.WithParams: shiroclient applies configs in order, and
// oracle.Call puts the caller's configs after its own.
//
// The answer is decoded into a structpb.Struct first because oracle.Call
// decodes into a proto message, and a flow answers a JSON object whose
// fields are substrate's, not this API's (see flowRun).
//
// A flow refuses a bad call (an unknown run, a stale generation, an input
// that fails its schema) with a JSON-RPC error. callFlow returns that as a
// business exception, the way the hand-written endpoints answered a bad
// request; any other error is returned as an error.
func (p *portal) callFlow(ctx context.Context, method string, params []any, configs ...shiroclient.Config) (*flowRun, *common.Exception, error) {
	configs = append(configs, shiroclient.WithParams(params))
	out, err := oracle.Call(p.orc, ctx, method, &emptypb.Empty{}, &structpb.Struct{}, configs...)
	if err != nil {
		if exc := flowRejection(ctx, err); exc != nil {
			return nil, exc, nil
		}
		return nil, nil, err
	}
	b, err := protojson.Marshal(out)
	if err != nil {
		return nil, nil, fmt.Errorf("%s: encode the answer: %w", method, err)
	}
	run := &flowRun{}
	if err := json.Unmarshal(b, run); err != nil {
		return nil, nil, fmt.Errorf("%s: decode the answer: %w", method, err)
	}
	return run, nil, nil
}

// flowRejection returns a business exception for a flow's refusal of a
// call, or nil when err is not one. A refusal is the JSON-RPC error data
// {"error": CODE, "message": TEXT} that substrate's route-failure answers.
func flowRejection(ctx context.Context, err error) *common.Exception {
	var perr *phylum.Error
	if !errors.As(err, &perr) {
		return nil
	}
	var data struct {
		Error   string `json:"error"`
		Message string `json:"message"`
	}
	if json.Unmarshal(perr.DataJSON(), &data) != nil || data.Error == "" {
		return nil
	}
	return svcerr.BusinessException(ctx, fmt.Sprintf("%s: %s", data.Error, data.Message))
}

// flowParams encodes positional parameters for a flow endpoint. A proto
// message is encoded with protojson and its proto field names, as
// oracle.Call encodes a request message, so the phylum reads the same JSON
// in both cases (for example "nationality": "NATIONALITY_GB").
func flowParams(values ...any) ([]any, error) {
	m := protojson.MarshalOptions{UseProtoNames: true}
	params := make([]any, len(values))
	for i, v := range values {
		msg, ok := v.(proto.Message)
		if !ok {
			params[i] = v
			continue
		}
		b, err := m.Marshal(msg)
		if err != nil {
			return nil, fmt.Errorf("encode parameter %d: %w", i, err)
		}
		params[i] = json.RawMessage(b)
	}
	return params, nil
}

// flowRun is the part of a claim flow's answer that the API uses. A start
// or an input answers run_id, state, gen and label. The get endpoint adds
// result (the finished claim), vars (the saved locals that :expose names)
// and error. encoding/json ignores the other fields substrate returns, so a
// substrate release that adds one does not break the oracle.
type flowRun struct {
	RunID  string     `json:"run_id"`
	State  string     `json:"state"`
	Label  string     `json:"label"`
	Result *claimData `json:"result"`
	Vars   *claimData `json:"vars"`
	Error  *flowError `json:"error"`
	Gen    int64      `json:"gen"`
}

// claimData is the claim as the flow keeps it: in vars while the claim
// waits, and in result once it is done. The fields are the JSON the oracle
// sent in, kept raw so protojson decodes them back into the API's messages.
type claimData struct {
	Status   string          `json:"status"`
	Details  json.RawMessage `json:"details"`
	Claimant json.RawMessage `json:"claimant"`
}

// flowError is why a run failed.
type flowError struct {
	Reason  string `json:"reason"`
	Label   string `json:"label"`
	Message string `json:"message"`
}

// flowStates maps a run's state to the API's ClaimState.
var flowStates = map[string]pb.ClaimState{
	"waiting": pb.ClaimState_CLAIM_STATE_WAITING,
	"done":    pb.ClaimState_CLAIM_STATE_DONE,
	"failed":  pb.ClaimState_CLAIM_STATE_FAILED,
}

// claim converts a flow answer to the API's Claim.
func (r *flowRun) claim() *pb.Claim {
	c := &pb.Claim{
		ClaimId: r.RunID,
		State:   flowStates[r.State],
		Gen:     r.Gen,
	}
	if r.State == "waiting" {
		c.Step = r.Label
	}
	if r.Error != nil {
		c.Error = r.Error.Message
		if c.Error == "" {
			c.Error = r.Error.Reason
		}
	}
	data := r.Result
	if data == nil {
		data = r.Vars
	}
	if data == nil {
		return c
	}
	// The flow stores what the oracle sent, so these decode; a field that
	// fails to decode is left empty rather than failing the whole read.
	u := protojson.UnmarshalOptions{DiscardUnknown: true}
	details := &pb.CreateClaimRequest{}
	if len(data.Details) > 0 && u.Unmarshal(data.Details, details) == nil {
		c.DateOfAccident = details.GetDateOfAccident()
		c.DamageAmount = details.GetDamageAmount()
		c.ClaimReason = details.GetClaimReason()
	}
	claimant := &pb.Claimant{}
	if len(data.Claimant) > 0 && u.Unmarshal(data.Claimant, claimant) == nil {
		c.Claimant = claimant
	}
	c.Status = pb.Status(pb.Status_value[data.Status])
	return c
}
