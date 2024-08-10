/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package protoutil

import (
	"bytes"
	"crypto/sha256"
	"encoding/asn1"
	"encoding/base64"
	"fmt"
	"math/big"

	cb "github.com/hyperledger/fabric-protos-go-apiv2/common"
	"google.golang.org/protobuf/proto"
)

// NewBlock constructs a block with no data and no metadata.
func NewBlock(seqNum uint64, previousHash []byte) *cb.Block {
	block := &cb.Block{}
	block.Header = &cb.BlockHeader{}
	block.Header.Number = seqNum
	block.Header.PreviousHash = previousHash
	block.Header.DataHash = []byte{}
	block.Data = &cb.BlockData{}

	var metadataContents [][]byte
	for i := 0; i < len(cb.BlockMetadataIndex_name); i++ {
		metadataContents = append(metadataContents, []byte{})
	}
	block.Metadata = &cb.BlockMetadata{Metadata: metadataContents}

	return block
}

type asn1Header struct {
	Number       *big.Int
	PreviousHash []byte
	DataHash     []byte
}

func BlockHeaderBytes(b *cb.BlockHeader) []byte {
	asn1Header := asn1Header{
		PreviousHash: b.PreviousHash,
		DataHash:     b.DataHash,
		Number:       new(big.Int).SetUint64(b.Number),
	}
	result, err := asn1.Marshal(asn1Header)
	if err != nil {
		// Errors should only arise for types which cannot be encoded, since the
		// BlockHeader type is known a-priori to contain only encodable types, an
		// error here is fatal and should not be propagated
		panic(err)
	}
	return result
}

func BlockHeaderHash(b *cb.BlockHeader) []byte {
	sum := sha256.Sum256(BlockHeaderBytes(b))
	return sum[:]
}

func BlockDataHash(b *cb.BlockData) []byte {
	sum := sha256.Sum256(bytes.Join(b.Data, nil))
	return sum[:]
}

// GetChannelIDFromBlockBytes returns channel ID given byte array which represents
// the block
func GetChannelIDFromBlockBytes(bytes []byte) (string, error) {
	block, err := UnmarshalBlock(bytes)
	if err != nil {
		return "", err
	}

	return GetChannelIDFromBlock(block)
}

// GetChannelIDFromBlock returns channel ID in the block
func GetChannelIDFromBlock(block *cb.Block) (string, error) {
	if block == nil || block.Data == nil || block.Data.Data == nil || len(block.Data.Data) == 0 {
		return "", fmt.Errorf("failed to retrieve channel id - block is empty")
	}
	var err error
	envelope, err := GetEnvelopeFromBlock(block.Data.Data[0])
	if err != nil {
		return "", err
	}
	payload, err := UnmarshalPayload(envelope.Payload)
	if err != nil {
		return "", err
	}

	if payload.Header == nil {
		return "", fmt.Errorf("failed to retrieve channel id - payload header is empty")
	}
	chdr, err := UnmarshalChannelHeader(payload.Header.ChannelHeader)
	if err != nil {
		return "", err
	}

	return chdr.ChannelId, nil
}

// GetMetadataFromBlock retrieves metadata at the specified index.
func GetMetadataFromBlock(block *cb.Block, index cb.BlockMetadataIndex) (*cb.Metadata, error) {
	if block.Metadata == nil {
		return nil, fmt.Errorf("no metadata in block")
	}

	if len(block.Metadata.Metadata) <= int(index) {
		return nil, fmt.Errorf("no metadata at index [%s]", index)
	}

	md := &cb.Metadata{}
	err := proto.Unmarshal(block.Metadata.Metadata[index], md)
	if err != nil {
		return nil, fmt.Errorf("error [%w] unmarshalling metadata at index [%s]", err, index)
	}
	return md, nil
}

// GetMetadataFromBlockOrPanic retrieves metadata at the specified index, or
// panics on error
func GetMetadataFromBlockOrPanic(block *cb.Block, index cb.BlockMetadataIndex) *cb.Metadata {
	md, err := GetMetadataFromBlock(block, index)
	if err != nil {
		panic(err)
	}
	return md
}

// CopyBlockMetadata copies metadata from one block into another
func CopyBlockMetadata(src *cb.Block, dst *cb.Block) {
	dst.Metadata = src.Metadata
	// Once copied initialize with rest of the
	// required metadata positions.
	InitBlockMetadata(dst)
}

// InitBlockMetadata initializes metadata structure
func InitBlockMetadata(block *cb.Block) {
	if block.Metadata == nil {
		block.Metadata = &cb.BlockMetadata{Metadata: [][]byte{{}, {}, {}, {}, {}}}
	} else if len(block.Metadata.Metadata) < int(cb.BlockMetadataIndex_COMMIT_HASH+1) {
		for i := int(len(block.Metadata.Metadata)); i <= int(cb.BlockMetadataIndex_COMMIT_HASH); i++ {
			block.Metadata.Metadata = append(block.Metadata.Metadata, []byte{})
		}
	}
}

func VerifyTransactionsAreWellFormed(block *cb.Block) error {
	if block == nil || block.Data == nil || len(block.Data.Data) == 0 {
		return fmt.Errorf("empty block")
	}

	// If we have a single transaction, and the block is a config block, then no need to check
	// well formed-ness, because there cannot be another transaction in the original block.
	if IsConfigBlock(block) {
		return nil
	}

	for i, rawTx := range block.Data.Data {
		env := &cb.Envelope{}
		if err := proto.Unmarshal(rawTx, env); err != nil {
			return fmt.Errorf("transaction %d is invalid: %v", i, err)
		}

		if len(env.Payload) == 0 {
			return fmt.Errorf("transaction %d has no payload", i)
		}

		if len(env.Signature) == 0 {
			return fmt.Errorf("transaction %d has no signature", i)
		}

		expected, err := proto.Marshal(env)
		if err != nil {
			return fmt.Errorf("failed re-marshaling envelope: %v", err)
		}

		if len(expected) < len(rawTx) {
			return fmt.Errorf("transaction %d has %d trailing bytes", i, len(rawTx)-len(expected))
		}
		if !bytes.Equal(expected, rawTx) {
			return fmt.Errorf("transaction %d (%s) does not match its raw form (%s)", i,
				base64.StdEncoding.EncodeToString(expected), base64.StdEncoding.EncodeToString(rawTx))
		}
	}

	return nil
}
