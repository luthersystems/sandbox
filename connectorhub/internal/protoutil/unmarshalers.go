/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package protoutil

import (
	"fmt"

	"github.com/hyperledger/fabric-protos-go-apiv2/common"
	"github.com/hyperledger/fabric-protos-go-apiv2/ledger/rwset"
	"github.com/hyperledger/fabric-protos-go-apiv2/ledger/rwset/kvrwset"
	"github.com/hyperledger/fabric-protos-go-apiv2/msp"
	"github.com/hyperledger/fabric-protos-go-apiv2/peer"
	"google.golang.org/protobuf/proto"
)

// the implicit contract of all these unmarshalers is that they
// will return a non-nil pointer whenever the error is nil

// UnmarshalBlock unmarshals bytes to a Block
func UnmarshalBlock(encoded []byte) (*common.Block, error) {
	block := &common.Block{}
	if err := proto.Unmarshal(encoded, block); err != nil {
		return nil, fmt.Errorf("error unmarshalling Block: %w", err)
	}
	return block, nil
}

// UnmarshalChaincodeDeploymentSpec unmarshals bytes to a ChaincodeDeploymentSpec
func UnmarshalChaincodeDeploymentSpec(code []byte) (*peer.ChaincodeDeploymentSpec, error) {
	cds := &peer.ChaincodeDeploymentSpec{}
	if err := proto.Unmarshal(code, cds); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeDeploymentSpec: %w", err)
	}
	return cds, nil
}

// UnmarshalChaincodeInvocationSpec unmarshals bytes to a ChaincodeInvocationSpec
func UnmarshalChaincodeInvocationSpec(encoded []byte) (*peer.ChaincodeInvocationSpec, error) {
	cis := &peer.ChaincodeInvocationSpec{}
	if err := proto.Unmarshal(encoded, cis); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeInvocationSpec: %w", err)
	}
	return cis, nil
}

// UnmarshalPayload unmarshals bytes to a Payload
func UnmarshalPayload(encoded []byte) (*common.Payload, error) {
	payload := &common.Payload{}
	if err := proto.Unmarshal(encoded, payload); err != nil {
		return nil, fmt.Errorf("error unmarshalling Payload: %w", err)
	}
	return payload, nil
}

// UnmarshalEnvelope unmarshals bytes to a Envelope
func UnmarshalEnvelope(encoded []byte) (*common.Envelope, error) {
	envelope := &common.Envelope{}
	if err := proto.Unmarshal(encoded, envelope); err != nil {
		return nil, fmt.Errorf("error unmarshalling Envelope: %w", err)
	}
	return envelope, nil
}

// UnmarshalChannelHeader unmarshals bytes to a ChannelHeader
func UnmarshalChannelHeader(bytes []byte) (*common.ChannelHeader, error) {
	chdr := &common.ChannelHeader{}
	if err := proto.Unmarshal(bytes, chdr); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChannelHeader: %w", err)
	}
	return chdr, nil
}

// UnmarshalChaincodeID unmarshals bytes to a ChaincodeID
func UnmarshalChaincodeID(bytes []byte) (*peer.ChaincodeID, error) {
	ccid := &peer.ChaincodeID{}
	if err := proto.Unmarshal(bytes, ccid); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeID: %w", err)
	}
	return ccid, nil
}

// UnmarshalSignatureHeader unmarshals bytes to a SignatureHeader
func UnmarshalSignatureHeader(bytes []byte) (*common.SignatureHeader, error) {
	sh := &common.SignatureHeader{}
	if err := proto.Unmarshal(bytes, sh); err != nil {
		return nil, fmt.Errorf("error unmarshalling SignatureHeader: %w", err)
	}
	return sh, nil
}

func UnmarshalSerializedIdentity(bytes []byte) (*msp.SerializedIdentity, error) {
	sid := &msp.SerializedIdentity{}
	if err := proto.Unmarshal(bytes, sid); err != nil {
		return nil, fmt.Errorf("error unmarshalling SerializedIdentity: %w", err)
	}
	return sid, nil
}

// UnmarshalHeader unmarshals bytes to a Header
func UnmarshalHeader(bytes []byte) (*common.Header, error) {
	hdr := &common.Header{}
	if err := proto.Unmarshal(bytes, hdr); err != nil {
		return nil, fmt.Errorf("error unmarshalling Header: %w", err)
	}
	return hdr, nil
}

// UnmarshalChaincodeHeaderExtension unmarshals bytes to a ChaincodeHeaderExtension
func UnmarshalChaincodeHeaderExtension(hdrExtension []byte) (*peer.ChaincodeHeaderExtension, error) {
	chaincodeHdrExt := &peer.ChaincodeHeaderExtension{}
	if err := proto.Unmarshal(hdrExtension, chaincodeHdrExt); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeHeaderExtension: %w", err)
	}
	return chaincodeHdrExt, nil
}

// UnmarshalProposalResponse unmarshals bytes to a ProposalResponse
func UnmarshalProposalResponse(prBytes []byte) (*peer.ProposalResponse, error) {
	proposalResponse := &peer.ProposalResponse{}
	if err := proto.Unmarshal(prBytes, proposalResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling ProposalResponse: %w", err)
	}
	return proposalResponse, nil
}

// UnmarshalChaincodeAction unmarshals bytes to a ChaincodeAction
func UnmarshalChaincodeAction(caBytes []byte) (*peer.ChaincodeAction, error) {
	chaincodeAction := &peer.ChaincodeAction{}
	if err := proto.Unmarshal(caBytes, chaincodeAction); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeAction: %w", err)
	}
	return chaincodeAction, nil
}

// UnmarshalResponse unmarshals bytes to a Response
func UnmarshalResponse(resBytes []byte) (*peer.Response, error) {
	response := &peer.Response{}
	if err := proto.Unmarshal(resBytes, response); err != nil {
		return nil, fmt.Errorf("error unmarshalling Response: %w", err)
	}
	return response, nil
}

// UnmarshalChaincodeEvents unmarshals bytes to a ChaincodeEvent
func UnmarshalChaincodeEvents(eBytes []byte) (*peer.ChaincodeEvent, error) {
	chaincodeEvent := &peer.ChaincodeEvent{}
	if err := proto.Unmarshal(eBytes, chaincodeEvent); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaicnodeEvent: %w", err)
	}
	return chaincodeEvent, nil
}

// UnmarshalProposalResponsePayload unmarshals bytes to a ProposalResponsePayload
func UnmarshalProposalResponsePayload(prpBytes []byte) (*peer.ProposalResponsePayload, error) {
	prp := &peer.ProposalResponsePayload{}
	if err := proto.Unmarshal(prpBytes, prp); err != nil {
		return nil, fmt.Errorf("error unmarshalling ProposalResponsePayload: %w", err)
	}
	return prp, nil
}

// UnmarshalProposal unmarshals bytes to a Proposal
func UnmarshalProposal(propBytes []byte) (*peer.Proposal, error) {
	prop := &peer.Proposal{}
	if err := proto.Unmarshal(propBytes, prop); err != nil {
		return nil, fmt.Errorf("error unmarshalling Proposal: %w", err)
	}
	return prop, nil
}

// UnmarshalTransaction unmarshals bytes to a Transaction
func UnmarshalTransaction(txBytes []byte) (*peer.Transaction, error) {
	tx := &peer.Transaction{}
	if err := proto.Unmarshal(txBytes, tx); err != nil {
		return nil, fmt.Errorf("error unmarshalling Transaction: %w", err)
	}
	return tx, nil
}

// UnmarshalChaincodeActionPayload unmarshals bytes to a ChaincodeActionPayload
func UnmarshalChaincodeActionPayload(capBytes []byte) (*peer.ChaincodeActionPayload, error) {
	cap := &peer.ChaincodeActionPayload{}
	if err := proto.Unmarshal(capBytes, cap); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeActionPayload: %w", err)
	}
	return cap, nil
}

// UnmarshalChaincodeProposalPayload unmarshals bytes to a ChaincodeProposalPayload
func UnmarshalChaincodeProposalPayload(bytes []byte) (*peer.ChaincodeProposalPayload, error) {
	cpp := &peer.ChaincodeProposalPayload{}
	if err := proto.Unmarshal(bytes, cpp); err != nil {
		return nil, fmt.Errorf("error unmarshalling ChaincodeProposalPayload: %w", err)
	}
	return cpp, nil
}

// UnmarshalTxReadWriteSet unmarshals bytes to a TxReadWriteSet
func UnmarshalTxReadWriteSet(bytes []byte) (*rwset.TxReadWriteSet, error) {
	rws := &rwset.TxReadWriteSet{}
	if err := proto.Unmarshal(bytes, rws); err != nil {
		return nil, fmt.Errorf("error unmarshalling TxReadWriteSet: %w", err)
	}
	return rws, nil
}

// UnmarshalKVRWSet unmarshals bytes to a KVRWSet
func UnmarshalKVRWSet(bytes []byte) (*kvrwset.KVRWSet, error) {
	rws := &kvrwset.KVRWSet{}
	if err := proto.Unmarshal(bytes, rws); err != nil {
		return nil, fmt.Errorf("error unmarshalling KVRWSet: %w", err)
	}
	return rws, nil
}

// UnmarshalHashedRWSet unmarshals bytes to a HashedRWSet
func UnmarshalHashedRWSet(bytes []byte) (*kvrwset.HashedRWSet, error) {
	hrws := &kvrwset.HashedRWSet{}
	if err := proto.Unmarshal(bytes, hrws); err != nil {
		return nil, fmt.Errorf("error unmarshalling HashedRWSet: %w", err)
	}
	return hrws, nil
}

// UnmarshalSignaturePolicy unmarshals bytes to a SignaturePolicyEnvelope
func UnmarshalSignaturePolicy(bytes []byte) (*common.SignaturePolicyEnvelope, error) {
	sp := &common.SignaturePolicyEnvelope{}
	if err := proto.Unmarshal(bytes, sp); err != nil {
		return nil, fmt.Errorf("error unmarshalling SignaturePolicyEnvelope: %w", err)
	}
	return sp, nil
}

// UnmarshalPayloadOrPanic unmarshals bytes to a Payload structure or panics
// on error
func UnmarshalPayloadOrPanic(encoded []byte) *common.Payload {
	payload, err := UnmarshalPayload(encoded)
	if err != nil {
		panic(err)
	}
	return payload
}

// UnmarshalEnvelopeOrPanic unmarshals bytes to an Envelope structure or panics
// on error
func UnmarshalEnvelopeOrPanic(encoded []byte) *common.Envelope {
	envelope, err := UnmarshalEnvelope(encoded)
	if err != nil {
		panic(err)
	}
	return envelope
}

// UnmarshalBlockOrPanic unmarshals bytes to an Block or panics
// on error
func UnmarshalBlockOrPanic(encoded []byte) *common.Block {
	block, err := UnmarshalBlock(encoded)
	if err != nil {
		panic(err)
	}
	return block
}

// UnmarshalChannelHeaderOrPanic unmarshals bytes to a ChannelHeader or panics
// on error
func UnmarshalChannelHeaderOrPanic(bytes []byte) *common.ChannelHeader {
	chdr, err := UnmarshalChannelHeader(bytes)
	if err != nil {
		panic(err)
	}
	return chdr
}

// UnmarshalSignatureHeaderOrPanic unmarshals bytes to a SignatureHeader or panics
// on error
func UnmarshalSignatureHeaderOrPanic(bytes []byte) *common.SignatureHeader {
	sighdr, err := UnmarshalSignatureHeader(bytes)
	if err != nil {
		panic(err)
	}
	return sighdr
}
