// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package oracle

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	pb "github.com/luthersystems/sandbox/api/pb/v1"
	srv "github.com/luthersystems/sandbox/api/srvpb/v1"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/version"
	"github.com/luthersystems/sandbox/phylum"
	"github.com/luthersystems/shiroclient-sdk-go/shiroclient"
	"github.com/luthersystems/svc/grpclogging"
	"github.com/sirupsen/logrus"
)

const (
	// TimestampFormat uses RFC3339 for all timestamps.
	TimestampFormat = time.RFC3339

	// phylumServiceName is the name reported by the phylum healthcheck
	// report.
	phylumServiceName = "sandbox-cc"

	// oracleServiceName is the name reported by the oracle healthcheck report.
	oracleServiceName = "sandbox-oracle"

	// healthCheckPath is used to override health check functionality.
	// IMPORTANT: this must be kept in sync with api/srvpb/*proto
	healthCheckPath = "/v1/health_check"

	// swaggerPath is used to serve the current swagger json.
	// IMPORTANT: this must be kept in sync with api/swagger/*json
	swaggerPath = "/swagger.json"

	// metricsPath is used to serve prometheus metrics.
	// IMPORTANT: this should not be accessible externally
	metricsPath = "/metrics"

	// metricsAddr is the http addr the prometheus server listens on.
	metricsAddr = ":9600"

	// DefaultRegion is the AWS default region.
	DefaultRegion = "eu-west-2"

	// HeaderReqID is the HTTP header used to (uniquely) identify requests and
	// associate log entries with individual requests for diagnosing errors.
	HeaderReqID = "X-Request-ID"
)

// DefaultConfig returns a default config.
func DefaultConfig() *Config {
	return &Config{
		Verbose:   true,
		EmulateCC: false,
		// IMPORTANT: Phylum bootstrap expects ListenAddress on :8080 for
		// FakeAuth IDP. Only change this if you know what you're doing!
		ListenAddress:   ":8080",
		PhylumVersion:   "test", // FIXME DELETEME
		PhylumPath:      "./phylum",
		GatewayEndpoint: "http://shiroclient_gateway:8082",
	}
}

// Config configures an oracle.
type Config struct {
	// Verbose increases logging.
	Verbose bool `yaml:"verbose"`
	// EmulateCC emulates chaincode in memory (for testing).
	EmulateCC bool `yaml:"emulate-cc"`
	// ListenAddress is an address the oracle HTTP listens on.
	ListenAddress string `yaml:"listen-address"`
	// PhylumVersion is the version of the phylum.
	PhylumVersion string `yaml:"phylum-version"`
	// PhylumPath is the the path for the business logic.
	PhylumPath string `yaml:"phylum-path"`
	// GatewayEndpoint is an address to the shiroclient gateway.
	GatewayEndpoint string `yaml:"gateway-endpoint"`
}

// Valid validates an oracle configuration.
func (c *Config) Valid() error {
	if c == nil {
		return fmt.Errorf("missing phylum config")
	}
	if c.ListenAddress == "" {
		return fmt.Errorf("missing listen address")
	}
	if c.PhylumVersion == "" {
		return fmt.Errorf("missing phylum version")
	}
	if c.PhylumPath == "" {
		return fmt.Errorf("missing phylum path")
	}
	if !c.EmulateCC && c.GatewayEndpoint == "" {
		return fmt.Errorf("missing gateway endpoint")
	}
	return nil
}

// Oracle provides services.
type Oracle struct {
	srv.UnimplementedSandboxServiceServer

	// log provides logging.
	logBase *logrus.Entry

	// phylum interacts with phylum.
	phylum *phylum.Client

	// txConfigs generates default transaction configs
	txConfigs func(context.Context, ...shiroclient.Config) []shiroclient.Config
}

// Option provides additional configuration to the oracle. Primarily for
// testing.
type Option func(*Oracle) error

// WithLogBase allows setting a custom base logger.
func WithLogBase(logBase *logrus.Entry) Option {
	return func(orc *Oracle) error {
		orc.logBase = logBase
		return nil
	}
}

// WithPhylum connects to shiroclient gateway.
func WithPhylum(gatewayEndpoint string) Option {
	return func(orc *Oracle) error {
		ph, err := phylum.New(gatewayEndpoint, orc.logBase)
		if err != nil {
			return fmt.Errorf("unable to initialize phylum: %w", err)
		}

		ph.GetLogMetadata = grpclogging.GetLogrusFields
		orc.phylum = ph
		return nil
	}
}

// WithMockPhylum runs the phylum in memory.
func WithMockPhylum(path string) Option {
	return WithMockPhylumFrom(path, nil)
}

// WithMockPhylumFrom runs the phylum in memory from a snapshot.
func WithMockPhylumFrom(path string, r io.Reader) Option {
	return func(orc *Oracle) error {
		orc.logBase.Infof("NewMock")
		ph, err := phylum.NewMockFrom(path, orc.logBase, r)
		if err != nil {
			return fmt.Errorf("unable to initialize mock phylum: %w", err)
		}
		ph.GetLogMetadata = grpclogging.GetLogrusFields
		orc.phylum = ph
		return nil
	}
}

// New constructs a new oracle.
func New(config *Config, opts ...Option) (*Oracle, error) {
	err := config.Valid()
	if err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}
	oracle := &Oracle{}
	oracle.logBase = logrus.StandardLogger().WithFields(nil)
	for _, opt := range opts {
		err := opt(oracle)
		if err != nil {
			return nil, err
		}
	}
	if oracle.phylum == nil {
		err := WithPhylum(config.GatewayEndpoint)(oracle)
		if err != nil {
			return nil, err
		}
	}

	oracle.txConfigs = txConfigs()

	return oracle, nil
}

func (orc *Oracle) log(ctx context.Context) *logrus.Entry {
	return grpclogging.GetLogrusEntry(ctx, orc.logBase)
}

func txConfigs() func(context.Context, ...shiroclient.Config) []shiroclient.Config {
	return func(ctx context.Context, extend ...shiroclient.Config) []shiroclient.Config {
		fields := grpclogging.GetLogrusFields(ctx)
		configs := []shiroclient.Config{
			shiroclient.WithLogrusFields(fields),
			shiroclient.WithContext(ctx),
		}
		if fields["req_id"] != nil {
			logrus.WithField("req_id", fields["req_id"]).Infof("setting request id")
			configs = append(configs, shiroclient.WithID(fmt.Sprint(fields["req_id"])))
		}
		configs = append(configs, extend...)
		return configs
	}
}

func phylumHealthCheck(ctx context.Context, orc *Oracle) []*pb.HealthCheckReport {
	sopts := orc.txConfigs(ctx)
	ccHealth, err := orc.phylum.HealthCheck(ctx, []string{"phylum"}, sopts...)
	if err != nil && !errors.Is(err, context.Canceled) {
		return []*pb.HealthCheckReport{&pb.HealthCheckReport{
			ServiceName:    phylumServiceName,
			ServiceVersion: "",
			Timestamp:      time.Now().Format(TimestampFormat),
			Status:         "DOWN",
		}}
	}
	reports := ccHealth.GetReports()
	for _, report := range reports {
		if strings.EqualFold(report.GetServiceName(), phylumServiceName) {
			setPhylumVersion(report.GetServiceVersion())
			break
		}
	}
	if getLastPhylumVersion() == "" {
		orc.log(ctx).Errorf("missing phylum version")
	}
	return reports
}

// HealthCheck checks this service and all dependent services to construct a
// health report. Returns a grpc error code if a service is down.
func (orc *Oracle) HealthCheck(ctx context.Context, req *pb.HealthCheckRequest) (*pb.HealthCheckResponse, error) {
	// No ACL: Open to everyone
	healthy := true
	var reports []*pb.HealthCheckReport
	if !req.GetOracleOnly() {
		reports = phylumHealthCheck(ctx, orc)
		for _, report := range reports {
			if !strings.EqualFold(report.GetStatus(), "UP") {
				healthy = false
				break
			}
		}
	}
	reports = append(reports, &pb.HealthCheckReport{
		ServiceName:    oracleServiceName,
		ServiceVersion: version.Version,
		Timestamp:      time.Now().Format(TimestampFormat),
		Status:         "UP",
	})
	resp := &pb.HealthCheckResponse{
		Reports: reports,
	}
	if !healthy {
		reportsJSON, err := json.Marshal(resp)
		if err != nil {
			orc.log(ctx).WithError(err).Errorf("Oracle unhealthy")
		} else {
			orc.log(ctx).WithField("reports_json", string(reportsJSON)).Errorf("Oracle unhealthy")
		}
	}

	return resp, nil
}

// CreateAccount is an example resource creation endpoint.
func (orc *Oracle) CreateAccount(ctx context.Context, in *pb.CreateAccountRequest) (*pb.CreateAccountResponse, error) {
	sopts := orc.txConfigs(ctx)
	return orc.phylum.CreateAccount(ctx, in, sopts...)
}

// GetAccount is an example query endpoint.
func (orc *Oracle) GetAccount(ctx context.Context, in *pb.GetAccountRequest) (*pb.GetAccountResponse, error) {
	sopts := orc.txConfigs(ctx)
	return orc.phylum.GetAccount(ctx, in, sopts...)
}

// Transfer is an example write operation.
func (orc *Oracle) Transfer(ctx context.Context, in *pb.TransferRequest) (*pb.TransferResponse, error) {
	sopts := orc.txConfigs(ctx)
	return orc.phylum.Transfer(ctx, in, sopts...)
}

// Close blocks the caller until all spawned go routines complete, then closes the phylum
func (orc *Oracle) Close() error {
	return orc.phylum.Close()
}
