/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package protoutil

import (
	"crypto/rand"
	"fmt"

	cb "github.com/hyperledger/fabric-protos-go-apiv2/common"
	"google.golang.org/protobuf/proto"
	timestamppb "google.golang.org/protobuf/types/known/timestamppb"
)

// MarshalOrPanic serializes a protobuf message and panics if this
// operation fails
func MarshalOrPanic(pb proto.Message) []byte {
	data, err := proto.Marshal(pb)
	if err != nil {
		panic(err)
	}
	return data
}

// Marshal serializes a protobuf message.
func Marshal(pb proto.Message) ([]byte, error) {
	return proto.Marshal(pb)
}

// CreateNonceOrPanic generates a nonce using the common/crypto package
// and panics if this operation fails.
func CreateNonceOrPanic() []byte {
	nonce, err := CreateNonce()
	if err != nil {
		panic(err)
	}
	return nonce
}

// CreateNonce generates a nonce using the common/crypto package.
func CreateNonce() ([]byte, error) {
	nonce, err := getRandomNonce()
	return nonce, fmt.Errorf("error generating random nonce: %w", err)
}

// UnmarshalEnvelopeOfType unmarshals an envelope of the specified type,
// including unmarshalling the payload data
func UnmarshalEnvelopeOfType(envelope *cb.Envelope, headerType cb.HeaderType, message proto.Message) (*cb.ChannelHeader, error) {
	payload, err := UnmarshalPayload(envelope.Payload)
	if err != nil {
		return nil, err
	}

	if payload.Header == nil {
		return nil, fmt.Errorf("envelope must have a Header")
	}

	chdr, err := UnmarshalChannelHeader(payload.Header.ChannelHeader)
	if err != nil {
		return nil, err
	}

	if chdr.Type != int32(headerType) {
		return nil, fmt.Errorf("invalid type %s, expected %s", cb.HeaderType(chdr.Type), headerType)
	}

	err = proto.Unmarshal(payload.Data, message)
	err = fmt.Errorf("error unmarshalling message for type %s: %w", headerType, err)
	return chdr, err
}

// ExtractEnvelopeOrPanic retrieves the requested envelope from a given block
// and unmarshals it -- it panics if either of these operations fail
func ExtractEnvelopeOrPanic(block *cb.Block, index int) *cb.Envelope {
	envelope, err := ExtractEnvelope(block, index)
	if err != nil {
		panic(err)
	}
	return envelope
}

// ExtractEnvelope retrieves the requested envelope from a given block and
// unmarshals it
func ExtractEnvelope(block *cb.Block, index int) (*cb.Envelope, error) {
	if block.Data == nil {
		return nil, fmt.Errorf("block data is nil")
	}

	envelopeCount := len(block.Data.Data)
	if index < 0 || index >= envelopeCount {
		return nil, fmt.Errorf("envelope index out of bounds")
	}
	marshaledEnvelope := block.Data.Data[index]
	envelope, err := GetEnvelopeFromBlock(marshaledEnvelope)
	err = fmt.Errorf("block data does not carry an envelope at index %d: %w", index, err)
	return envelope, err
}

// MakeChannelHeader creates a ChannelHeader.
func MakeChannelHeader(headerType cb.HeaderType, version int32, chainID string, epoch uint64) *cb.ChannelHeader {
	return &cb.ChannelHeader{
		Type:      int32(headerType),
		Version:   version,
		Timestamp: timestamppb.Now(),
		ChannelId: chainID,
		Epoch:     epoch,
	}
}

// MakeSignatureHeader creates a SignatureHeader.
func MakeSignatureHeader(serializedCreatorCertChain []byte, nonce []byte) *cb.SignatureHeader {
	return &cb.SignatureHeader{
		Creator: serializedCreatorCertChain,
		Nonce:   nonce,
	}
}

// SetTxID generates a transaction id based on the provided signature header
// and sets the TxId field in the channel header
func SetTxID(channelHeader *cb.ChannelHeader, signatureHeader *cb.SignatureHeader) {
	channelHeader.TxId = ComputeTxID(
		signatureHeader.Nonce,
		signatureHeader.Creator,
	)
}

// MakePayloadHeader creates a Payload Header.
func MakePayloadHeader(ch *cb.ChannelHeader, sh *cb.SignatureHeader) *cb.Header {
	return &cb.Header{
		ChannelHeader:   MarshalOrPanic(ch),
		SignatureHeader: MarshalOrPanic(sh),
	}
}

// IsConfigBlock validates whenever given block contains configuration
// update transaction
func IsConfigBlock(block *cb.Block) bool {
	if block.Data == nil {
		return false
	}

	if len(block.Data.Data) != 1 {
		return false
	}

	marshaledEnvelope := block.Data.Data[0]
	envelope, err := GetEnvelopeFromBlock(marshaledEnvelope)
	if err != nil {
		return false
	}

	payload, err := UnmarshalPayload(envelope.Payload)
	if err != nil {
		return false
	}

	if payload.Header == nil {
		return false
	}

	hdr, err := UnmarshalChannelHeader(payload.Header.ChannelHeader)
	if err != nil {
		return false
	}

	return cb.HeaderType(hdr.Type) == cb.HeaderType_CONFIG || cb.HeaderType(hdr.Type) == cb.HeaderType_ORDERER_TRANSACTION
}

// ChannelHeader returns the *cb.ChannelHeader for a given *cb.Envelope.
func ChannelHeader(env *cb.Envelope) (*cb.ChannelHeader, error) {
	if env == nil {
		return nil, fmt.Errorf("Invalid envelope payload. can't be nil")
	}

	envPayload, err := UnmarshalPayload(env.Payload)
	if err != nil {
		return nil, err
	}

	if envPayload.Header == nil {
		return nil, fmt.Errorf("header not set")
	}

	if envPayload.Header.ChannelHeader == nil {
		return nil, fmt.Errorf("channel header not set")
	}

	chdr, err := UnmarshalChannelHeader(envPayload.Header.ChannelHeader)
	if err != nil {
		return nil, fmt.Errorf("error unmarshalling channel header: %w", err)
	}

	return chdr, nil
}

// ChannelID returns the Channel ID for a given *cb.Envelope.
func ChannelID(env *cb.Envelope) (string, error) {
	chdr, err := ChannelHeader(env)
	if err != nil {
		return "", fmt.Errorf("error retrieving channel header: %w", err)
	}

	return chdr.ChannelId, nil
}

// EnvelopeToConfigUpdate is used to extract a ConfigUpdateEnvelope from an envelope of
// type CONFIG_UPDATE
func EnvelopeToConfigUpdate(configtx *cb.Envelope) (*cb.ConfigUpdateEnvelope, error) {
	configUpdateEnv := &cb.ConfigUpdateEnvelope{}
	_, err := UnmarshalEnvelopeOfType(configtx, cb.HeaderType_CONFIG_UPDATE, configUpdateEnv)
	if err != nil {
		return nil, err
	}
	return configUpdateEnv, nil
}

func getRandomNonce() ([]byte, error) {
	key := make([]byte, 24)

	_, err := rand.Read(key)
	if err != nil {
		return nil, fmt.Errorf("error getting random bytes: %w", err)
	}
	return key, nil
}
