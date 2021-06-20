// Copyright © 2021 Luther Systems, Ltd. All right reserved.

/*
HTTP Middleware

The oracle defines a simple system for http middleware built around functions
with the following signature:

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

	"github.com/golang/protobuf/jsonpb"
	"github.com/golang/protobuf/proto"
	"github.com/google/uuid"
	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	"github.com/grpc-ecosystem/grpc-gateway/utilities"
	pb "github.com/luthersystems/sandbox/api/pb"
	srv "github.com/luthersystems/sandbox/api/srvpb"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/version"
	"github.com/luthersystems/svc/svcerr"
)

type httpMiddleware interface {
	Wrap(http.Handler) http.Handler
}

// middlewareChain is a list of middleware specified in order from outermost to
// innermost.
type middlewareChain []httpMiddleware

func (c middlewareChain) Wrap(h http.Handler) http.Handler {
	for i := len(c) - 1; i >= 0; i-- {
		h = c[i].Wrap(h)
	}
	return h
}

// middlewareFunc is a function that implements httpMiddleware.
type middlewareFunc func(http.Handler) http.Handler

func (fn middlewareFunc) Wrap(h http.Handler) http.Handler {
	return fn(h)
}

type httpRouteOverrides map[string]http.Handler

func (m httpRouteOverrides) Wrap(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if route, ok := m[r.URL.Path]; ok {
			route.ServeHTTP(w, r)
			return
		}
		h.ServeHTTP(w, r)
	})
}

// addServerHeader includes the version of the oracle within the Server HTTP
// response header.
func addServerHeader(next http.Handler) http.Handler {
	srvHeaderOracle := fmt.Sprintf("%s/%s", oracleServiceName, version.Version)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		srvHeader := srvHeaderOracle
		cachedPhylumVersion := getLastPhylumVersion()
		if cachedPhylumVersion != "" {
			srvHeader = fmt.Sprintf("%s %s/%s", srvHeader, phylumServiceName, cachedPhylumVersion)
		}
		w.Header().Set("Server", srvHeader)
		next.ServeHTTP(w, r)
	})
}

// addRequestID ensures all incoming HTTP requests have an id header and
// automatically includes an id header to HTTP responses.  See HeaderReqID.
func addRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get(HeaderReqID) // FIXME remove this?
		if reqID == "" {
			reqID = uuid.New().String()
			r.Header.Set(HeaderReqID, reqID)
		}
		w.Header().Set(HeaderReqID, reqID)
		next.ServeHTTP(w, r)
	})
}

// healthCheckHandler intercepts the healthcheck endpoint to return 503 on
// error.
func healthCheckHandler(oracle *Oracle, client srv.SandboxProcessorClient) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		sendResponse := func(resp *pb.GetHealthCheckResponse, responseCode int) {
			err := writeProtoHTTP(w, responseCode, resp)
			if err != nil {
				oracle.log(ctx).WithError(err).Errorf("health handler response error")
			}
		}
		exceptionf := func(format string, v ...interface{}) *pb.GetHealthCheckResponse {
			ex := svcerr.BusinessException(ctx, fmt.Sprintf(format, v...))
			return &pb.GetHealthCheckResponse{Exception: ex}
		}

		reqProto := &pb.GetHealthCheckRequest{}
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
			resp = &pb.GetHealthCheckResponse{
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
