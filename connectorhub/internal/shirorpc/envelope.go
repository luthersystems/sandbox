package shirorpc

import (
	"encoding/json"
)

// Envelope is a type used for chaincode responses that are in JSON
// format. The envelope adds a "dirty" boolean that is intended to
// signify whether the transaction has made committable changes to the
// ledger.
type Envelope struct {
	// Payload contains the remainder of the JSON response.
	Payload json.RawMessage `json:"payload"`

	// Dirty indicates whether the transaction has made committable
	// changes to the ledger.
	Dirty bool `json:"dirty"`
}
