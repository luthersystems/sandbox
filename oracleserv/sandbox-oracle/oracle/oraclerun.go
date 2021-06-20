// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package oracle

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/NYTimes/gziphandler"
	grpcmiddleware "github.com/grpc-ecosystem/go-grpc-middleware"
	grpc_prometheus "github.com/grpc-ecosystem/go-grpc-prometheus"
	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	srv "github.com/luthersystems/sandbox/api/srvpb"
	"github.com/luthersystems/sandbox/api/swagger"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/version"
	"github.com/luthersystems/svc/grpclogging"
	"github.com/luthersystems/svc/logmon"
	"github.com/luthersystems/svc/midware"
	"github.com/luthersystems/svc/svcerr"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
)

// gatewayForwardedHeaders are HTTP headers which the grpc-gateway will encode
// as grpc request metadata and forward to the oracle grpc server.  Forwarded
// headers may be used for authentication flows, request tracing, etc.
var gatewayForwardedHeaders = [...]string{
	"Cookie",
	"X-Forwarded-For",
	"User-Agent",
	"X-Forwarded-User-Agent",
	"Referer",
	HeaderReqID,
}

// getLastPhylumVersion retrieves the last set phylum version and is concurrency safe.
var getLastPhylumVersion func() string

// setPhylumVersion sets the last seen phylum version and is concurrency safe.
var setPhylumVersion func(string)

func init() {
	// Provider per endpoint histograms (at expense of memory/performance).
	grpc_prometheus.EnableClientHandlingTimeHistogram(
		grpc_prometheus.WithHistogramBuckets(prometheus.ExponentialBuckets(0.05, 1.25, 25)),
	)

	// Expose log severity counts to prometheus.
	logrus.AddHook(logmon.NewPrometheusHook())

	{ // set version helpers and prometheus metric
		versionTotal := prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "version_total",
				Help: "How many versions seen, partitioned by oracle and phylum.",
			},
			[]string{"oracle_name", "oracle_version", "phylum_name", "phylum_version"},
		)
		var mut sync.RWMutex
		// cachedPhylumVersion is a phylum version string retrieved on oracle boot
		// from the phylum healthcheck.
		var cachedPhylumVersion string
		getLastPhylumVersion = func() string {
			mut.RLock()
			defer mut.RUnlock()
			return cachedPhylumVersion
		}
		setPhylumVersion = func(v string) {
			mut.Lock()
			defer mut.Unlock()
			cachedPhylumVersion = v
			if cachedPhylumVersion != "" {
				versionTotal.WithLabelValues(oracleServiceName, version.Version, phylumServiceName, cachedPhylumVersion).Inc()
			}
		}
		prometheus.MustRegister(versionTotal)
	}
}

// Run starts the oracle.
func Run(config *Config) error {
	trySendError := func(c chan<- error, err error) {
		if err == nil {
			return
		}
		select {
		case c <- err:
		default:
		}
	}
	errServe := make(chan error, 1)
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	opts := []Option{}
	if config.EmulateCC {
		opts = append(opts, WithMockPhylum(config.PhylumVersion, config.PhylumPath))
	}
	oracle, err := New(config, opts...)
	if err != nil {
		return err
	}
	defer oracle.Close()

	if err != nil {
		return err
	}

	if config.Verbose {
		logrus.SetLevel(logrus.DebugLevel)
	}
	oracle.log(ctx).WithFields(logrus.Fields{
		"version":          version.Version,
		"emulate_cc":       config.EmulateCC,
		"listen_address":   config.ListenAddress,
		"phylum_version":   config.PhylumVersion,
		"phylum_path":      config.PhylumPath,
		"gateway_endpoint": config.GatewayEndpoint,
	}).Infof(oracleServiceName)

	// Start a grpc server listening on the unix socket at grpcAddr
	grpcAddr := "/tmp/oracle.grpc.sock"
	grpcServer := grpc.NewServer(
		grpc.UnaryInterceptor(grpcmiddleware.ChainUnaryServer(
			grpclogging.LogrusMethodInterceptor(
				oracle.logBase,
				grpclogging.UpperBoundTimer(time.Millisecond),
				grpclogging.RealTime()),
			svcerr.AppErrorUnaryInterceptor(oracle.log))))
	srv.RegisterSandboxProcessorServer(grpcServer, oracle)
	listener, err := net.Listen("unix", grpcAddr)
	if err != nil {
		return fmt.Errorf("grpc listen: %w", err)
	}
	go func() {
		trySendError(errServe, grpcServer.Serve(listener))
	}()

	// Create a grpc client which connects to grpcAddr
	dialctx, dialcancel := context.WithDeadline(ctx, time.Now().Add(time.Second))
	defer dialcancel()
	grpcConn, err := grpc.DialContext(dialctx, "unix://"+grpcAddr,
		grpc.WithInsecure(),
		grpc.WithUnaryInterceptor(grpcmiddleware.ChainUnaryClient(
			grpc_prometheus.UnaryClientInterceptor)))
	if err != nil {
		return fmt.Errorf("grpc dial: %w", err)
	}
	grpcSandboxProcessorClient := srv.NewSandboxProcessorClient(grpcConn)

	// Create a grpc-gateway handler which talks to the oracle through the grpc
	// client.  Wrap the grpc-gateway with middleware to produce complete
	// service handler.
	grpcGatewayInit(oracle.log)
	jsonapi, err := grpcGateway(ctx, grpcSandboxProcessorClient)
	if err != nil {
		return err
	}
	swaggerHandler, err := swagger.HTTPHandler("oracle")
	if err != nil {
		return fmt.Errorf("swagger definition error: %v", err)
	}
	middleware := midware.Chain{
		// The gzip and trace header middlewares to appear early in the chain
		// because of how important it is that they happen for essentially all
		// requests.
		midware.Func(gziphandler.GzipHandler),
		midware.TraceHeaders(HeaderReqID, true),
		addServerHeader(),
		// PathOverrides and other middleware that may serve requests or have
		// potential failure states should appear below here so they may rely
		// on the presence of the generic utility middleware above.
		midware.PathOverrides{
			swaggerPath:     swaggerHandler,
			healthCheckPath: healthCheckHandler(oracle, grpcSandboxProcessorClient),
		},
	}
	httpHandler := middleware.Wrap(jsonapi)

	go func() {
		oracle.log(ctx).Infof("init healthcheck")
		hctx, hcancel := context.WithDeadline(ctx, time.Now().Add(10*time.Second))
		defer hcancel()
		phylumHealthCheck(hctx, oracle)
	}()

	go func() {
		oracle.log(ctx).Infof("oracle listen")
		trySendError(errServe, http.ListenAndServe(config.ListenAddress, httpHandler))
	}()

	go func() {
		// metrics server
		h := http.NewServeMux()
		h.Handle(metricsPath, promhttp.Handler())
		s := &http.Server{
			Addr:         metricsAddr,
			WriteTimeout: 10 * time.Second,
			Handler:      h,
		}
		oracle.log(ctx).Infof("prometheus listen")
		trySendError(errServe, s.ListenAndServe())
	}()

	// Both methods grpcServer.Start and http.ListenAndServe will block
	// forever.  An error in either the grpc server or the http server will
	// appear in the errServe channel and halt the process.
	return <-errServe
}

// grpcGatewayInit performs global configuration that only needs to be done
// once per process.
func grpcGatewayInit(log func(ctx context.Context) *logrus.Entry) {
	runtime.HTTPError = svcerr.ErrIntercept(log)
	runtime.DisallowUnknownFields()
}

// grpcGateway constructs a new grpc-gateway to serve the application's JSON API.
func grpcGateway(ctx context.Context, client srv.SandboxProcessorClient) (*runtime.ServeMux, error) {
	opts := []runtime.ServeMuxOption{
		runtime.WithIncomingHeaderMatcher(incomingHeaderMatcher),
		runtime.WithMarshalerOption(runtime.MIMEWildcard, &runtime.JSONPb{OrigName: true}),
	}
	mux := runtime.NewServeMux(opts...)
	err := srv.RegisterSandboxProcessorHandlerClient(ctx, mux, client)
	if err != nil {
		return nil, err
	}
	return mux, nil
}

func incomingHeaderMatcher(h string) (string, bool) {
	for i := range gatewayForwardedHeaders {
		if strings.EqualFold(h, gatewayForwardedHeaders[i]) {
			return h, true
		}
	}
	return "", false
}
