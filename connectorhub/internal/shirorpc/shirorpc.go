// Package shirorpc has utilities for constructing messages compatible with
// shiroclient and substrate.
package shirorpc

import (
	"encoding/json"
	"fmt"
)

type shiroRequest struct{}

// Transient returns the transient data for the request.
func (s *shiroRequest) Transient() map[string][]byte {
	return make(map[string][]byte) // TODO
}

// ArgumentsBytes returns the arguments for the request.
func (s *shiroRequest) ArgumentsBytes() []byte {
	return nil // TODO:
}

// MakeRequest constructs a shiroclient request message.
func MakeRequest(r json.RawMessage) (*shiroRequest, error) {
	return &shiroRequest{}, nil
}

type shiroResponse struct {
	r json.RawMessage
}

// Valid determines if the response is valid.
func (s *shiroResponse) Valid() error {
	if len(s.r) == 0 {
		return fmt.Errorf("missing response")
	}
	return nil
}

// MakeResponse constructs a shiroclient response message.
func MakeResponse(r json.RawMessage) (*shiroResponse, error) {
	return &shiroResponse{
		r: r,
	}, nil
}
