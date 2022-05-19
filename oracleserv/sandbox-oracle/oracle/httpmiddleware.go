// Copyright © 2021 Luther Systems, Ltd. All right reserved.

/*
Package oracle defines a simple system for http middleware built around
functions with the following signature:

	func Wrap(h http.Handler) http.Handler

The middleware are chained together using the middlewareChain type which can
wrap the grpc-gateway to augment how it serves the API.
*/
package oracle

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	//lint:ignore SA1019 we are not ready to upgrade proto lib yet
	"github.com/golang/protobuf/jsonpb"
	//lint:ignore SA1019 we are not ready to upgrade proto lib yet
	"github.com/golang/protobuf/proto"
	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	"github.com/grpc-ecosystem/grpc-gateway/utilities"
	pb "github.com/luthersystems/sandbox/api/pb/v1"
	srv "github.com/luthersystems/sandbox/api/srvpb/v1"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/version"
	"github.com/luthersystems/svc/midware"
	"github.com/luthersystems/svc/svcerr"
)

// addServerHeader includes the version of the oracle within the Server HTTP
// response header.
func addServerHeader() midware.Middleware {
	return midware.ServerResponseHeader(
		midware.ServerFixed(oracleServiceName, version.Version),
		func() string {
			cachedPhylumVersion := getLastPhylumVersion()
			if cachedPhylumVersion != "" {
				return fmt.Sprintf("%s/%s", phylumServiceName, cachedPhylumVersion)
			}
			return ""
		})
}

// healthCheckHandler intercepts the healthcheck endpoint to return 503 on
// error.
func healthCheckHandler(oracle *Oracle, client srv.SandboxServiceClient) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		sendResponse := func(resp *pb.HealthCheckResponse, responseCode int) {
			err := writeProtoHTTP(w, responseCode, resp)
			if err != nil {
				oracle.log(ctx).WithError(err).Errorf("health handler response error")
			}
		}
		exceptionf := func(format string, v ...interface{}) *pb.HealthCheckResponse {
			ex := svcerr.BusinessException(ctx, fmt.Sprintf(format, v...))
			return &pb.HealthCheckResponse{Exception: ex}
		}

		reqProto := &pb.HealthCheckRequest{}
		if err := r.ParseForm(); err != nil {
			sendResponse(exceptionf("invalid request: %s", err), http.StatusBadRequest)
			return
		}
		err := runtime.PopulateQueryParameters(reqProto, r.Form, utilities.NewDoubleArray(nil))
		if err != nil {
			sendResponse(exceptionf("invalid request: %s", err), http.StatusBadRequest)
			return
		}

		resp, err := client.HealthCheck(ctx, reqProto)
		if err != nil || len(resp.GetReports()) == 0 {
			switch ctx.Err() {
			case context.Canceled:
				oracle.log(ctx).Infof("healthcheck: context canceled")
				// nothing more to do
				return
			case context.DeadlineExceeded:
				oracle.log(ctx).WithError(err).Errorf("context deadline")
			default:
				oracle.log(ctx).WithError(err).Errorf("missing processor client healthcheck response")
			}
			resp = &pb.HealthCheckResponse{
				Reports: []*pb.HealthCheckReport{
					&pb.HealthCheckReport{
						ServiceName:    oracleServiceName,
						ServiceVersion: version.Version,
						Timestamp:      time.Now().Format(TimestampFormat),
						Status:         "DOWN",
					},
				},
			}
			sendResponse(resp, http.StatusServiceUnavailable)
			return
		}

		for _, report := range resp.GetReports() {
			// NOTE: we assume resp is empty on error from above health check call
			if !strings.EqualFold(report.GetStatus(), "UP") {
				sendResponse(resp, http.StatusServiceUnavailable)
				return
			}
		}
		sendResponse(resp, http.StatusOK)
	})
}

func writeProtoHTTP(w http.ResponseWriter, code int, msg proto.Message) error {
	var b bytes.Buffer
	marshaler := &jsonpb.Marshaler{OrigName: true}
	err := marshaler.Marshal(&b, msg)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		return fmt.Errorf("protobuf marshal: %w", err)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_, err = io.Copy(w, &b)
	if err != nil {
		return fmt.Errorf("write response: %w", err)
	}
	return nil
}
