// Package shirorpc has utilities for constructing messages compatible with
// shiroclient and substrate.
package shirorpc

import (
	"encoding/json"
	"fmt"
	"strings"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

const (
	// TODO: why is this connector endpoint not being called!?
	connectorEndpoint = "$ch_callback"
	repTransientKey   = "$ch_rep"
)

type shiroRequest struct {
	requestID string
	r         json.RawMessage
}

type transient map[string][]byte

func (s *transient) String() string {
	if s == nil {
		return ""
	}
	p := make(map[string]string)
	for k, v := range *s {
		p[k] = string(v)
	}

	return fmt.Sprintf("%v", p)
}

// Transient returns the transient data for the request.
func (s *shiroRequest) Transient() (transient, error) {
	m := make(map[string][]byte)
	reqCopy := make([]byte, len(s.r))
	copy(reqCopy, s.r)
	m[repTransientKey] = reqCopy
	return m, nil
}

// ArgumentsBytes returns the arguments for the request.
func (s *shiroRequest) ArgumentsBytes() ([]byte, error) {
	type Body struct {
		RequestID string `json:"request_id"`
	}

	body := &Body{
		RequestID: s.requestID,
	}

	args := []*Body{body}

	metas := map[string]string{
		"$shiro_phylum": "latest",
	}

	return jsonRPCBytes(connectorEndpoint, s.requestID, args, metas)
}

// MakeRequest constructs a shiroclient request message.
func MakeRequest(reqID string, r json.RawMessage) (*shiroRequest, error) {
	return &shiroRequest{
		requestID: reqID,
		r:         r,
	}, nil
}

// Error is a generic application error
type Error interface {
	// Code returns a numeric code categorizing the error.
	Code() int

	// Message returns a generic error message that corresponds to the error Code.
	Message() string

	// DataJSON returns JSON data returned by the application with the error,
	// if any was provided.  The slice returned by DataJSON will either be
	// empty or it will contain valid serialized JSON data.
	DataJSON() []byte

	// Error implements the error interface.
	Error() string
}

// errorString extracts a message from the error.
func errorString(e Error) string {
	if len(e.DataJSON()) > 0 {
		return fmt.Sprintf("%s: %s", e.Message(), e.DataJSON())
	}
	return e.Message()
}

// jsonrpc returns a json-rpc request map with the given method, id, and
// params.
//
// Omitting params is intepretted as passing an empty slice (e.g.
// []interface{}{}) to default to the strictest possible intepretation -- a
// shiro endpoint defined to take zero arguments.  Passing an empty map would
// work for endpoints of any arity but that is not necessarily cleanly handled
// in a phylum.  Because of a blockchain's inherent immutability a strict
// default should result in a cleaner committed ledger.
func jsonrpc(method string, id interface{}, params interface{}, metas map[string]string) (map[string]interface{}, error) {
	if params == nil {
		params = []interface{}{}
	}
	m := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
		"id":      id,
	}
	for k, v := range metas {
		if !strings.HasPrefix(k, "$") {
			return nil, fmt.Errorf("invalid meta param [%s]", k)
		}
		m[k] = v
	}
	return m, nil
}

// jsonRPCBytes returns a json-rpc request encoded as JSON
func jsonRPCBytes(method string, id interface{}, params interface{}, metas map[string]string) ([]byte, error) {
	m, err := jsonrpc(method, id, params, metas)
	if err != nil {
		return nil, err
	}
	return json.Marshal(m)
}

type jsonRPCError struct {
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
	Code    int             `json:"code"`
}

type jsonRPCErrorWrapper struct {
	e *jsonRPCError
}

// Code implements Error.
func (e *jsonRPCErrorWrapper) Code() int {
	return e.e.Code
}

// Message implements Error.
func (e *jsonRPCErrorWrapper) Message() string {
	return e.e.Message
}

// DataJSON implements Error.
func (e *jsonRPCErrorWrapper) DataJSON() []byte {
	if len(e.e.Data) == 0 {
		return e.e.Data
	}
	b := make([]byte, len(e.e.Data))
	copy(b, e.e.Data)
	return b
}

// Error implements error.
func (e *jsonRPCErrorWrapper) Error() string {
	return errorString(e)
}

// JSONRPCResponse is a json-rpc response
type JSONRPCResponse struct {
	ID       interface{}     `json:"id"`
	RPCError *jsonRPCError   `json:"error"`
	JSONRPC  string          `json:"jsonrpc"`
	TxID     string          `json:"$transaction_id"`
	Result   json.RawMessage `json:"result"`
}

// NewJSONRPCResonse constructs a response from bytes.
func MakeResponse(respBytes []byte) (*JSONRPCResponse, error) {
	resp := &JSONRPCResponse{}
	err := json.Unmarshal(respBytes, resp)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// UnmarshalTo unmarshals the response's result to dst.
func (r *JSONRPCResponse) UnmarshalTo(dst interface{}) error {
	message, ok := dst.(proto.Message)
	if ok {
		return protojson.Unmarshal([]byte(r.Result), message)
	}
	return json.Unmarshal([]byte(r.Result), dst)
}

// ResultJSON returns the raw JSON result from the response.
func (r *JSONRPCResponse) ResultJSON() []byte {
	if len(r.Result) == 0 {
		return nil
	}

	b := make([]byte, len(r.Result))
	copy(b, r.Result)
	return b
}

// TransactionID returns the transaction ID from the response.
func (r *JSONRPCResponse) TransactionID() string {
	return r.TxID
}

// Error returns the error from the response, if there was any.
func (r *JSONRPCResponse) Error() Error {
	if r.RPCError == nil {
		return nil
	}
	return &jsonRPCErrorWrapper{r.RPCError}
}
