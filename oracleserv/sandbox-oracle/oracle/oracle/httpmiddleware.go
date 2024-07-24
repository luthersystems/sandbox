// Copyright © 2024 Luther Systems, Ltd. All right reserved.

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

	healthcheck "buf.build/gen/go/luthersystems/protos/protocolbuffers/go/healthcheck/v1"
	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"github.com/grpc-ecosystem/grpc-gateway/v2/utilities"
	"github.com/luthersystems/svc/midware"
	"github.com/luthersystems/svc/svcerr"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

// addServerHeader includes the version of the oracle within the Server HTTP
// response header.
func (orc *Oracle) addServerHeader() midware.Middleware {
	return midware.ServerResponseHeader(
		midware.ServerFixed(orc.serviceName, orc.version),
		func() string {
			cachedPhylumVersion := orc.getLastPhylumVersion()
			if cachedPhylumVersion != "" {
				return fmt.Sprintf("%s/%s", orc.phylumServiceName, cachedPhylumVersion)
			}
			return ""
		})
}

// healthCheckHandler intercepts the healthcheck endpoint to return 503 on
// error.
func (orc *Oracle) healthCheckHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		sendResponse := func(resp *healthcheck.GetHealthCheckResponse, responseCode int) {
			err := writeProtoHTTP(w, responseCode, resp)
			if err != nil {
				orc.log(ctx).WithError(err).Errorf("health handler response error")
			}
		}
		exceptionf := func(format string, v ...interface{}) *healthcheck.GetHealthCheckResponse {
			ex := svcerr.BusinessException(ctx, fmt.Sprintf(format, v...))
			return &healthcheck.GetHealthCheckResponse{Exception: ex}
		}

		reqProto := &healthcheck.GetHealthCheckRequest{}
		if err := r.ParseForm(); err != nil {
			sendResponse(exceptionf("invalid request: %s", err), http.StatusBadRequest)
			return
		}
		err := runtime.PopulateQueryParameters(reqProto, r.Form, utilities.NewDoubleArray(nil))
		if err != nil {
			sendResponse(exceptionf("invalid request: %s", err), http.StatusBadRequest)
			return
		}

		resp, err := orc.GetHealthCheck(ctx, reqProto)
		if err != nil || len(resp.GetReports()) == 0 {
			switch ctx.Err() {
			case context.Canceled:
				orc.log(ctx).Infof("healthcheck: context canceled")
				// nothing more to do
				return
			case context.DeadlineExceeded:
				orc.log(ctx).WithError(err).Errorf("context deadline")
			default:
				orc.log(ctx).WithError(err).Errorf("missing processor client healthcheck response")
			}
			resp = &healthcheck.GetHealthCheckResponse{
				Reports: []*healthcheck.HealthCheckReport{
					{
						ServiceName:    orc.serviceName,
						ServiceVersion: orc.version,
						Timestamp:      time.Now().Format(timestampFormat),
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
	marshaler := &protojson.MarshalOptions{UseProtoNames: true}
	b, err := marshaler.Marshal(msg)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		return fmt.Errorf("protobuf marshal: %w", err)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_, err = io.Copy(w, bytes.NewBuffer(b))
	if err != nil {
		return fmt.Errorf("write response: %w", err)
	}
	return nil
}
