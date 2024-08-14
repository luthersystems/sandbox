/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package protoutil

import (
	"bytes"
	"crypto/sha256"
	b64 "encoding/base64"
	"fmt"

	"github.com/hyperledger/fabric-protos-go-apiv2/common"
	"github.com/hyperledger/fabric-protos-go-apiv2/peer"
	"google.golang.org/protobuf/proto"
)

// GetPayloads gets the underlying payload objects in a TransactionAction
func GetPayloads(txActions *peer.TransactionAction) (*peer.ChaincodeActionPayload, *peer.ChaincodeAction, error) {
	// TODO: pass in the tx type (in what follows we're assuming the
	// type is ENDORSER_TRANSACTION)
	ccPayload, err := UnmarshalChaincodeActionPayload(txActions.Payload)
	if err != nil {
		return nil, nil, err
	}

	if ccPayload.Action == nil || ccPayload.Action.ProposalResponsePayload == nil {
		return nil, nil, fmt.Errorf("no payload in ChaincodeActionPayload")
	}
	pRespPayload, err := UnmarshalProposalResponsePayload(ccPayload.Action.ProposalResponsePayload)
	if err != nil {
		return nil, nil, err
	}

	if pRespPayload.Extension == nil {
		return nil, nil, fmt.Errorf("response payload is missing extension")
	}

	respPayload, err := UnmarshalChaincodeAction(pRespPayload.Extension)
	if err != nil {
		return ccPayload, nil, err
	}
	return ccPayload, respPayload, nil
}

// GetEnvelopeFromBlock gets an envelope from a block's Data field.
func GetEnvelopeFromBlock(data []byte) (*common.Envelope, error) {
	// Block always begins with an envelope
	var err error
	env := &common.Envelope{}
	if err = proto.Unmarshal(data, env); err != nil {
		return nil, fmt.Errorf("error unmarshalling Envelope: %w", err)
	}

	return env, nil
}

// Signer is the interface needed to sign a transaction
type Signer interface {
	Sign(msg []byte) ([]byte, error)
	Serialize() ([]byte, error)
}

// CreateSignedTx assembles an Envelope message from proposal, endorsements,
// and a signer. This function should be called by a client when it has
// collected enough endorsements for a proposal to create a transaction and
// submit it to peers for ordering
func CreateSignedTx(
	proposal *peer.Proposal,
	signer Signer,
	resps ...*peer.ProposalResponse,
) (*common.Envelope, error) {
	if len(resps) == 0 {
		return nil, fmt.Errorf("at least one proposal response is required")
	}

	if signer == nil {
		return nil, fmt.Errorf("signer is required when creating a signed transaction")
	}

	// the original header
	hdr, err := UnmarshalHeader(proposal.Header)
	if err != nil {
		return nil, err
	}

	// the original payload
	pPayl, err := UnmarshalChaincodeProposalPayload(proposal.Payload)
	if err != nil {
		return nil, err
	}

	// check that the signer is the same that is referenced in the header
	signerBytes, err := signer.Serialize()
	if err != nil {
		return nil, err
	}

	shdr, err := UnmarshalSignatureHeader(hdr.SignatureHeader)
	if err != nil {
		return nil, err
	}

	if !bytes.Equal(signerBytes, shdr.Creator) {
		return nil, fmt.Errorf("signer must be the same as the one referenced in the header")
	}

	// ensure that all actions are bitwise equal and that they are successful
	var a1 []byte
	for n, r := range resps {
		if r.Response.Status < 200 || r.Response.Status >= 400 {
			return nil, fmt.Errorf("proposal response was not successful, error code %d, msg %s", r.Response.Status, r.Response.Message)
		}

		if n == 0 {
			a1 = r.Payload
			continue
		}

		if !bytes.Equal(a1, r.Payload) {
			return nil, fmt.Errorf("ProposalResponsePayloads do not match (base64): '%s' vs '%s'",
				b64.StdEncoding.EncodeToString(r.Payload), b64.StdEncoding.EncodeToString(a1))
		}
	}

	// fill endorsements according to their uniqueness
	endorsersUsed := make(map[string]struct{})
	var endorsements []*peer.Endorsement
	for _, r := range resps {
		if r.Endorsement == nil {
			continue
		}
		key := string(r.Endorsement.Endorser)
		if _, used := endorsersUsed[key]; used {
			continue
		}
		endorsements = append(endorsements, r.Endorsement)
		endorsersUsed[key] = struct{}{}
	}

	if len(endorsements) == 0 {
		return nil, fmt.Errorf("no endorsements")
	}

	// create ChaincodeEndorsedAction
	cea := &peer.ChaincodeEndorsedAction{ProposalResponsePayload: resps[0].Payload, Endorsements: endorsements}

	// obtain the bytes of the proposal payload that will go to the transaction
	propPayloadBytes, err := GetBytesProposalPayloadForTx(pPayl)
	if err != nil {
		return nil, err
	}

	// serialize the chaincode action payload
	cap := &peer.ChaincodeActionPayload{ChaincodeProposalPayload: propPayloadBytes, Action: cea}
	capBytes, err := GetBytesChaincodeActionPayload(cap)
	if err != nil {
		return nil, err
	}

	// create a transaction
	taa := &peer.TransactionAction{Header: hdr.SignatureHeader, Payload: capBytes}
	taas := make([]*peer.TransactionAction, 1)
	taas[0] = taa
	tx := &peer.Transaction{Actions: taas}

	// serialize the tx
	txBytes, err := GetBytesTransaction(tx)
	if err != nil {
		return nil, err
	}

	// create the payload
	payl := &common.Payload{Header: hdr, Data: txBytes}
	paylBytes, err := GetBytesPayload(payl)
	if err != nil {
		return nil, err
	}

	// sign the payload
	sig, err := signer.Sign(paylBytes)
	if err != nil {
		return nil, err
	}

	// here's the envelope
	return &common.Envelope{Payload: paylBytes, Signature: sig}, nil
}

// CreateProposalResponse creates a proposal response.
func CreateProposalResponse(
	hdrbytes []byte,
	payl []byte,
	response *peer.Response,
	results []byte,
	events []byte,
	ccid *peer.ChaincodeID,
	signingEndorser Signer,
) (*peer.ProposalResponse, error) {
	hdr, err := UnmarshalHeader(hdrbytes)
	if err != nil {
		return nil, err
	}

	// obtain the proposal hash given proposal header, payload and the
	// requested visibility
	pHashBytes, err := GetProposalHash1(hdr, payl)
	if err != nil {
		return nil, fmt.Errorf("error computing proposal hash: %w", err)
	}

	// get the bytes of the proposal response payload - we need to sign them
	prpBytes, err := GetBytesProposalResponsePayload(pHashBytes, response, results, events, ccid)
	if err != nil {
		return nil, err
	}

	// serialize the signing identity
	endorser, err := signingEndorser.Serialize()
	if err != nil {
		return nil, fmt.Errorf("error serializing signing identity: %w", err)
	}

	// sign the concatenation of the proposal response and the serialized
	// endorser identity with this endorser's key
	signature, err := signingEndorser.Sign(append(prpBytes, endorser...))
	if err != nil {
		return nil, fmt.Errorf("could not sign the proposal response payload: %w", err)
	}

	resp := &peer.ProposalResponse{
		// Timestamp: TODO!
		Version: 1, // TODO: pick right version number
		Endorsement: &peer.Endorsement{
			Signature: signature,
			Endorser:  endorser,
		},
		Payload: prpBytes,
		Response: &peer.Response{
			Status:  200,
			Message: "OK",
		},
	}

	return resp, nil
}

// CreateProposalResponseFailure creates a proposal response for cases where
// endorsement proposal fails either due to a endorsement failure or a
// chaincode failure (chaincode response status >= shim.ERRORTHRESHOLD)
func CreateProposalResponseFailure(
	hdrbytes []byte,
	payl []byte,
	response *peer.Response,
	results []byte,
	events []byte,
	chaincodeName string,
) (*peer.ProposalResponse, error) {
	hdr, err := UnmarshalHeader(hdrbytes)
	if err != nil {
		return nil, err
	}

	// obtain the proposal hash given proposal header, payload and the requested visibility
	pHashBytes, err := GetProposalHash1(hdr, payl)
	if err != nil {
		return nil, fmt.Errorf("error computing proposal hash: %w", err)
	}

	// get the bytes of the proposal response payload
	prpBytes, err := GetBytesProposalResponsePayload(pHashBytes, response, results, events, &peer.ChaincodeID{Name: chaincodeName})
	if err != nil {
		return nil, err
	}

	resp := &peer.ProposalResponse{
		// Timestamp: TODO!
		Payload:  prpBytes,
		Response: response,
	}

	return resp, nil
}

// GetSignedProposal returns a signed proposal given a Proposal message and a
// signing identity
func GetSignedProposal(prop *peer.Proposal, signer Signer) (*peer.SignedProposal, error) {
	// check for nil argument
	if prop == nil || signer == nil {
		return nil, fmt.Errorf("nil arguments")
	}

	propBytes, err := proto.Marshal(prop)
	if err != nil {
		return nil, err
	}

	signature, err := signer.Sign(propBytes)
	if err != nil {
		return nil, err
	}

	return &peer.SignedProposal{ProposalBytes: propBytes, Signature: signature}, nil
}

// MockSignedEndorserProposalOrPanic creates a SignedProposal with the
// passed arguments
func MockSignedEndorserProposalOrPanic(
	channelID string,
	cs *peer.ChaincodeSpec,
	creator,
	signature []byte,
) (*peer.SignedProposal, *peer.Proposal) {
	prop, _, err := CreateChaincodeProposal(
		common.HeaderType_ENDORSER_TRANSACTION,
		channelID,
		&peer.ChaincodeInvocationSpec{ChaincodeSpec: cs},
		creator)
	if err != nil {
		panic(err)
	}

	propBytes, err := proto.Marshal(prop)
	if err != nil {
		panic(err)
	}

	return &peer.SignedProposal{ProposalBytes: propBytes, Signature: signature}, prop
}

func MockSignedEndorserProposal2OrPanic(
	channelID string,
	cs *peer.ChaincodeSpec,
	signer Signer,
) (*peer.SignedProposal, *peer.Proposal) {
	serializedSigner, err := signer.Serialize()
	if err != nil {
		panic(err)
	}

	prop, _, err := CreateChaincodeProposal(
		common.HeaderType_ENDORSER_TRANSACTION,
		channelID,
		&peer.ChaincodeInvocationSpec{ChaincodeSpec: &peer.ChaincodeSpec{}},
		serializedSigner)
	if err != nil {
		panic(err)
	}

	sProp, err := GetSignedProposal(prop, signer)
	if err != nil {
		panic(err)
	}

	return sProp, prop
}

// GetBytesProposalPayloadForTx takes a ChaincodeProposalPayload and returns
// its serialized version according to the visibility field
func GetBytesProposalPayloadForTx(
	payload *peer.ChaincodeProposalPayload,
) ([]byte, error) {
	// check for nil argument
	if payload == nil {
		return nil, fmt.Errorf("nil arguments")
	}

	// strip the transient bytes off the payload
	cppNoTransient := &peer.ChaincodeProposalPayload{Input: payload.Input, TransientMap: nil}
	cppBytes, err := GetBytesChaincodeProposalPayload(cppNoTransient)
	if err != nil {
		return nil, err
	}

	return cppBytes, nil
}

// GetProposalHash2 gets the proposal hash - this version
// is called by the committer where the visibility policy
// has already been enforced and so we already get what
// we have to get in ccPropPayl
func GetProposalHash2(header *common.Header, ccPropPayl []byte) ([]byte, error) {
	// check for nil argument
	if header == nil ||
		header.ChannelHeader == nil ||
		header.SignatureHeader == nil ||
		ccPropPayl == nil {
		return nil, fmt.Errorf("nil arguments")
	}

	hash := sha256.New()
	// hash the serialized Channel Header object
	hash.Write(header.ChannelHeader)
	// hash the serialized Signature Header object
	hash.Write(header.SignatureHeader)
	// hash the bytes of the chaincode proposal payload that we are given
	hash.Write(ccPropPayl)
	return hash.Sum(nil), nil
}

// GetProposalHash1 gets the proposal hash bytes after sanitizing the
// chaincode proposal payload according to the rules of visibility
func GetProposalHash1(header *common.Header, ccPropPayl []byte) ([]byte, error) {
	// check for nil argument
	if header == nil ||
		header.ChannelHeader == nil ||
		header.SignatureHeader == nil ||
		ccPropPayl == nil {
		return nil, fmt.Errorf("nil arguments")
	}

	// unmarshal the chaincode proposal payload
	cpp, err := UnmarshalChaincodeProposalPayload(ccPropPayl)
	if err != nil {
		return nil, err
	}

	ppBytes, err := GetBytesProposalPayloadForTx(cpp)
	if err != nil {
		return nil, err
	}

	hash2 := sha256.New()
	// hash the serialized Channel Header object
	hash2.Write(header.ChannelHeader)
	// hash the serialized Signature Header object
	hash2.Write(header.SignatureHeader)
	// hash of the part of the chaincode proposal payload that will go to the tx
	hash2.Write(ppBytes)
	return hash2.Sum(nil), nil
}

// GetOrComputeTxIDFromEnvelope gets the txID present in a given transaction
// envelope. If the txID is empty, it constructs the txID from nonce and
// creator fields in the envelope.
func GetOrComputeTxIDFromEnvelope(txEnvelopBytes []byte) (string, error) {
	txEnvelope, err := UnmarshalEnvelope(txEnvelopBytes)
	if err != nil {
		return "", fmt.Errorf("error getting txID from envelope: %w", err)
	}

	txPayload, err := UnmarshalPayload(txEnvelope.Payload)
	if err != nil {
		return "", fmt.Errorf("error getting txID from payload: %w", err)
	}

	if txPayload.Header == nil {
		return "", fmt.Errorf("error getting txID from header: payload header is nil")
	}

	chdr, err := UnmarshalChannelHeader(txPayload.Header.ChannelHeader)
	if err != nil {
		return "", fmt.Errorf("error getting txID from channel header: %w", err)
	}

	if chdr.TxId != "" {
		return chdr.TxId, nil
	}

	sighdr, err := UnmarshalSignatureHeader(txPayload.Header.SignatureHeader)
	if err != nil {
		return "", fmt.Errorf("error getting nonce and creator for computing txID: %w", err)
	}

	txid := ComputeTxID(sighdr.Nonce, sighdr.Creator)
	return txid, nil
}
