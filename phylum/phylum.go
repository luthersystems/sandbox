// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package phylum

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/mock"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/private"
	"github.com/sirupsen/logrus"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

// Config is an alias (not a distinct type)
type Config = shiroclient.Config

// defaultConfigs is used by the client as the starting config for most phylum
// calls.
var defaultConfigs = []func() (Config, error){
	private.WithSeed,
}

// phylumMethod describes a json-rpc method defined in the phylum's router.
// phylumMethod contains the method name and any special configuration to use
// instead of the default config.
type phylumMethod struct {
	method string
	config []func() (Config, error)
}

var (
	phylumCreateAccount = &phylumMethod{
		method: "create_account",
	}
	phylumGetAccount = &phylumMethod{
		method: "get_account",
	}
	phylumTransfer = &phylumMethod{
		method: "transfer",
	}
)

func joinConfig(base []func() (Config, error), add []Config) (conf []Config, err error) {
	nbase := len(base)
	conf = make([]Config, nbase+len(add))
	for i := range defaultConfigs {
		conf[i], err = defaultConfigs[i]()
		if err != nil {
			return nil, fmt.Errorf("default shiroclient config %d: %w", i, err)
		}
	}
	copy(conf[nbase:], add)
	return conf, nil
}

// cmdParams is a helper to construct positional arguments to pass to a shiro cmd.
func cmdParams(params ...proto.Message) []interface{} {
	if len(params) == 0 {
		return []interface{}{}
	}
	m := &protojson.MarshalOptions{UseProtoNames: true}
	jsparams := make([]interface{}, len(params))
	for i, p := range params {
		jsparams[i] = &jsProtoMessage{
			Message: p,
			m:       m,
		}
	}
	return jsparams
}

type jsProtoMessage struct {
	proto.Message
	m *protojson.MarshalOptions
}

func (msg *jsProtoMessage) MarshalJSON() ([]byte, error) {
	b, err := msg.m.Marshal(msg.Message)
	if err != nil {
		return nil, err
	}
	return b, nil
}

// Client is a phylum client.
type Client struct {
	log            *logrus.Entry
	rpc            shiroclient.ShiroClient
	GetLogMetadata func(context.Context) logrus.Fields
	closeFunc      func() error
}

// New returns a new phylum client.
func New(endpoint string, log *logrus.Entry) (*Client, error) {
	opts := []Config{
		shiroclient.WithEndpoint(endpoint),
		shiroclient.WithLogrusFields(log.Data),
	}
	client := &Client{
		log: log,
		rpc: shiroclient.NewRPC(opts),
	}
	return client, nil
}

// NewMock returns a mock phylum client.
func NewMock(phylumPath string, log *logrus.Entry) (*Client, error) {
	return NewMockFrom(phylumPath, log, nil)
}

// NewMockFrom returns a mock phylum client restored from a DB snapshot.
func NewMockFrom(phylumPath string, log *logrus.Entry, r io.Reader) (*Client, error) {
	clientOpts := []Config{
		shiroclient.WithLogrusFields(log.Data),
	}
	mockOpts := []mock.Option{
		mock.WithSnapshotReader(r),
	}
	mock, err := shiroclient.NewMock(clientOpts, mockOpts...)
	if err != nil {
		return nil, err
	}
	if r == nil {
		err = mock.Init(shiroclient.EncodePhylumBytes([]byte(phylumPath)))
		if err != nil {
			return nil, err
		}
	}
	client := &Client{
		log:       log,
		rpc:       mock,
		closeFunc: mock.Close,
	}
	return client, nil
}

func (s *Client) callMethod(ctx context.Context, m *phylumMethod, params []interface{}, out proto.Message, config []Config) (err error) {
	configBase := m.config
	if configBase == nil {
		configBase = defaultConfigs
	}
	config, err = joinConfig(configBase, config)
	if err != nil {
		return err
	}
	err = s.sdkCall(ctx, m.method, params, out, config)
	if err != nil {
		return err
	}
	return nil
}

// shiroCall is a helper to make RPC calls.
func (s *Client) sdkCall(ctx context.Context, cmd string, params interface{}, rep proto.Message, clientConfigs []Config) error {
	configs := make([]Config, 0, len(clientConfigs)+2)
	configs = append(configs, shiroclient.WithParams(params))
	configs = append(configs, clientConfigs...)
	configs = append(configs, shiroclient.WithContext(ctx))
	resp, err := s.rpc.Call(ctx, cmd, configs...)
	if err != nil {
		if shiroclient.IsTimeoutError(err) {
			s.logEntry(ctx).WithError(err).Errorf("shiroclient timeout")
			return status.Error(codes.Unavailable, "timeout in blockchain network")
		}
		return err
	}
	if e := resp.Error(); e != nil {
		// json-rpc protocol error
		s.logEntry(ctx).WithFields(logrus.Fields{
			"cmd":          cmd,
			"jsonrpc_code": e.Code(),
			// IMPORTANT: we cannot log this since it may contain PII.
			//"jsonrpc_data":    string(jsonResp),
			"jsonrpc_message": e.Message(),
		}).Errorf("json-rpc error received from phylum")
		// Attempt to extract an error message string in the JSON
		// response, and bubble up an error that can be displayed on the
		// frontend. This allows `route-failure` string responses to be
		// displayed on the frontend.
		if ejs := e.DataJSON(); ejs != nil {
			var errMsg string
			err := json.Unmarshal(ejs, &errMsg)
			if err == nil {
				return errors.New(errMsg)
			}
		}
		// The error data wasn't a JSON string message, revert to a masked
		// error to avoid potentially leaking senstive/confusing objects to the
		// frontend.
		return fmt.Errorf("unknown phylum error")
	}
	if rep == nil {
		// nothing to unmarshal
		return nil
	}
	err = protojson.Unmarshal(resp.ResultJSON(), rep)
	if err != nil {
		s.logEntry(ctx).
			// IMPORTANT: we cannot log this since it may contain PII.
			//WithField("debug_json", string(resp.ResultJSON())).
			WithError(err).Errorf("Shiro RPC result could not be decoded")
		return err
	}
	return nil
}

// MockSnapshot copies the current state of the mock backend out to the supplied
// io.Writer.
func (s *Client) MockSnapshot(w io.Writer) error {
	mock, ok := s.rpc.(shiroclient.MockShiroClient)
	if !ok {
		return fmt.Errorf("client rpc does not not support snapshots")
	}
	return mock.Snapshot(w)
}

// Close closes the client if necessary.
func (s *Client) Close() error {
	if s.closeFunc == nil {
		return nil
	}
	return s.closeFunc()
}

func (s *Client) logFields(ctx context.Context) logrus.Fields {
	if s.GetLogMetadata == nil {
		return nil
	}
	return s.GetLogMetadata(ctx)
}

func (s *Client) logEntry(ctx context.Context) *logrus.Entry {
	return s.log.WithFields(s.logFields(ctx))
}

// HealthCheck performs health check on phylum.
func (s *Client) HealthCheck(ctx context.Context, services []string, config ...Config) (*pb.HealthCheckResponse, error) {
	resp, err := shiroclient.RemoteHealthCheck(ctx, s.rpc, services, config...)
	if err != nil {
		return nil, err
	}
	return convertHealthResponse(resp), nil
}

func convertHealthResponse(health shiroclient.HealthCheck) *pb.HealthCheckResponse {
	reports := health.Reports()
	healthpb := &pb.HealthCheckResponse{
		Reports: make([]*pb.HealthCheckReport, len(reports)),
	}
	for i, report := range reports {
		healthpb.Reports[i] = convertHealthReport(report)
	}
	return healthpb
}

func convertHealthReport(report shiroclient.HealthCheckReport) *pb.HealthCheckReport {
	return &pb.HealthCheckReport{
		Timestamp:      report.Timestamp(),
		Status:         report.Status(),
		ServiceName:    report.ServiceName(),
		ServiceVersion: report.ServiceVersion(),
	}
}

// CreateAccount is an example endpoint to create a resource
func (s *Client) CreateAccount(ctx context.Context, req *pb.CreateAccountRequest, config ...Config) (*pb.CreateAccountResponse, error) {
	resp := &pb.CreateAccountResponse{}
	err := s.callMethod(ctx, phylumCreateAccount, cmdParams(req), resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// GetAccount is an example query endpoint
func (s *Client) GetAccount(ctx context.Context, req *pb.GetAccountRequest, config ...Config) (*pb.GetAccountResponse, error) {
	resp := &pb.GetAccountResponse{}
	err := s.callMethod(ctx, phylumGetAccount, cmdParams(req), resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// Transfer is an example transaction
func (s *Client) Transfer(ctx context.Context, req *pb.TransferRequest, config ...Config) (*pb.TransferResponse, error) {
	resp := &pb.TransferResponse{}
	err := s.callMethod(ctx, phylumTransfer, cmdParams(req), resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}
