// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package phylum

import (
	"context"
	"fmt"
	"io"

	pb "github.com/luthersystems/sandbox/api/pb/v1"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/mock"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient/private"
	"github.com/sirupsen/logrus"
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
	method     string
	transforms []*private.Transform
	config     []func() (Config, error)
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
	phylumCreateClient = &phylumMethod{
		method: "create_client",
		transforms: []*private.Transform{
			&private.Transform{
				ContextPath: ".client",
				Header: &private.TransformHeader{
					ProfilePaths: []string{".client_id"},
					PrivatePaths: []string{".iban"},
					Encryptor:    private.EncryptorAES256,
					Compressor:   private.CompressorZlib,
				}}},
	}

	phylumGetClient = &phylumMethod{
		method: "get_client",
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

func (s *Client) callMethod(ctx context.Context, m *phylumMethod, in proto.Message, out proto.Message, clientConfigs []Config) (err error) {
	configBase := m.config
	if configBase == nil {
		configBase = defaultConfigs
	}
	clientConfigs, err = joinConfig(configBase, clientConfigs)
	if err != nil {
		return err
	}

	wrap := private.WrapCall(ctx, s.rpc, m.method, m.transforms...)
	err = wrap(in, out, clientConfigs...)
	if err != nil {
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
	err := s.callMethod(ctx, phylumCreateAccount, req, resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// GetAccount is an example query endpoint
func (s *Client) GetAccount(ctx context.Context, req *pb.GetAccountRequest, config ...Config) (*pb.GetAccountResponse, error) {
	resp := &pb.GetAccountResponse{}
	err := s.callMethod(ctx, phylumGetAccount, req, resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// Transfer is an example transaction
func (s *Client) Transfer(ctx context.Context, req *pb.TransferRequest, config ...Config) (*pb.TransferResponse, error) {
	resp := &pb.TransferResponse{}
	err := s.callMethod(ctx, phylumTransfer, req, resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// CreateClient creates a new client with private details.
func (s *Client) CreateClient(ctx context.Context, req *pb.CreateClientRequest, config ...Config) (*pb.CreateClientResponse, error) {
	resp := &pb.CreateClientResponse{}
	err := s.callMethod(ctx, phylumCreateClient, req, resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// GetClient retrieves private client details.
func (s *Client) GetClient(ctx context.Context, req *pb.GetClientRequest, config ...Config) (*pb.GetClientResponse, error) {
	resp := &pb.GetClientResponse{}
	err := s.callMethod(ctx, phylumGetClient, req, resp, config)
	if err != nil {
		return nil, err
	}
	return resp, nil
}
