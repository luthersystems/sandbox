// Package chaininfo is a library for processing fabric protobufs, and Luther
// specific data structures maintained on-chain.
package chaininfo

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"

	cb "github.com/hyperledger/fabric-protos-go-apiv2/common"
	rwset "github.com/hyperledger/fabric-protos-go-apiv2/ledger/rwset"
	fabricpeer "github.com/hyperledger/fabric-protos-go-apiv2/peer"
	"github.com/luthersystems/sandbox/connectorhub/internal/protoutil"
	"github.com/olekukonko/tablewriter"
	"github.com/sirupsen/logrus"
	"google.golang.org/protobuf/proto"
)

const (
	LutherEventKey                    = "luther"
	LutherEventName                   = "txEventName"
	LutherEventRequestID              = "txRequestID"
	LutherEventTxTimestamp            = "txTimestamp"
	LutherConnectorEventPrefix        = "$connector_events:"
	LutherConnectorEventContextPrefix = "$cr:"
	LutherConnectorEventContextPDC    = "private"
	MaxConnectorEventsPerTx           = 10
)

var skipLifecycleRWSet = true

type TransactionID string

type CommonBlock struct {
	cb.Block
}

func (s *CommonBlock) Write(w io.Writer) {
	if s == nil || w == nil {
		return
	}
	if blk, err := NewBlock(&s.Block); err != nil {
		logrus.WithError(err).Error("new block")
	} else {
		blk.Write(w)
	}
}

// Block is a container for the transaction information.
type Block struct {
	hash          string
	transactions  []*Transaction
	txValidations []TxValidation
	blockNum      uint64
	size          int
}

func (s *Block) GetValidation(txNum int) *TxValidation {
	if s == nil || txNum < 0 || txNum >= len(s.txValidations) {
		missing := TxValidation(-1)
		return &missing
	}
	return &s.txValidations[txNum]
}

// formatWithTrailingDots truncates the input string to the specified length
// and adds trailing dots if the original string was longer.
func formatWithTrailingDots(input string, length int) string {
	if len(input) > length {
		return fmt.Sprintf("%.*s...", length, input)
	}
	return input
}

func (b *Block) Write(w io.Writer) {
	if w == nil {
		return
	}
	if b == nil {
		fmt.Fprint(w, "empty block")
		return
	}
	table := tablewriter.NewWriter(w)
	table.SetHeader([]string{"Block Num", "Hash", "Num Txs", "Size (bytes)"})
	table.SetCaption(true, "Block Summary")
	table.Append([]string{
		fmt.Sprintf("%d", b.blockNum),
		formatWithTrailingDots(b.hash, 6),
		fmt.Sprintf("%d", len(b.transactions)),
		fmt.Sprintf("%d", b.size),
	})
	table.Render() // Send output
	fmt.Fprintln(w)
	for i := range b.transactions {
		b.WriteTx(i, w)
	}
}

func prettyWriteVal(b []byte) string {
	var jsonObj interface{}

	// Try to unmarshal the bytes into a generic JSON object
	if err := json.Unmarshal(b, &jsonObj); err == nil {
		// If unmarshaling was successful, return the first 100 characters of JSON representation
		jsonStr, _ := json.MarshalIndent(jsonObj, "", "  ")
		if len(jsonStr) > 100 {
			return string(jsonStr[:100]) + "..."
		}
		return string(jsonStr)
	}

	return "non-JSON"
}

func (b *Block) WriteTx(i int, w io.Writer) {
	if w == nil {
		return
	}
	if i < 0 || i >= len(b.transactions) {
		return
	}
	t := b.transactions[i]
	table := tablewriter.NewWriter(w)
	table.SetHeader([]string{"ID", "Validation", "Chaincode ID", "Luther Event", "Event Size (bytes)", "Size (bytes)"})
	table.SetCaption(true, fmt.Sprintf("Transactions (block=[%d])", b.blockNum))
	details := t.GetDetails()
	event := details.GetEvent()
	table.Append([]string{
		formatWithTrailingDots(string(t.GetID()), 6),
		b.GetValidation(i).GetReason(),
		event.GetChaincodeId(),
		event.String(),
		fmt.Sprintf("%d", len(event.GetPayload())),
		fmt.Sprintf("%d", t.GetSize()),
	})
	table.Render()
	fmt.Fprintln(w)

	for _, nsRWSet := range details.GetNamespaceReadWriteSet() {
		if nsRWSet.GetNamespace() == "_lifecycle" && skipLifecycleRWSet {
			continue
		}
		rwSet := nsRWSet.GetReadWriteSet()

		table = tablewriter.NewWriter(w)
		table.SetCaption(true, fmt.Sprintf("Read Set (namespace=[%s], txid=[%s])", nsRWSet.GetNamespace(), t.GetID()))
		table.SetHeader([]string{"Key", "Version"})
		for _, record := range rwSet.GetReadSet() {
			table.Append([]string{
				record.GetKey(),
				record.GetVersion().String(),
			})
		}
		table.Render()
		fmt.Fprintln(w)

		table = tablewriter.NewWriter(w)
		table.SetCaption(true, fmt.Sprintf("Write Set [%s]", nsRWSet.GetNamespace()))
		table.SetHeader([]string{"Key", "Val (size)", "Val"})
		for _, record := range rwSet.GetWriteSet() {
			table.Append([]string{
				record.GetKey(),
				fmt.Sprintf("%d", len(record.GetVal())),
				prettyWriteVal(record.GetVal()),
			})
		}

		table.Render()
		fmt.Fprintln(w)
	}
}

// GetHash returns block hash.
func (b *Block) GetHash() string {
	if b == nil {
		return ""
	}
	return b.hash
}

// GetBlockNum returns the block number.
func (b *Block) GetBlockNum() uint64 {
	if b == nil {
		return 0
	}
	return b.blockNum
}

// GetTransactions returns the transactions in the block.
func (b *Block) GetTransactions() []*Transaction {
	if b == nil {
		return nil
	}
	txsCopy := make([]*Transaction, len(b.transactions))
	copy(txsCopy, b.transactions)
	return txsCopy
}

// Transaction is a container for the transaction information exported
// by QueryBlock.
type Transaction struct {
	details *TransactionDetails
	id      TransactionID
	num     int
	size    int
}

func (t *Transaction) GetNumber() int {
	if t == nil {
		return -1
	}
	return t.num
}

// ID is the transaction ID.
func (t *Transaction) GetID() TransactionID {
	if t == nil || t.id == "" {
		return TransactionID("n/a")
	}
	return t.id
}

func (t *Transaction) GetSize() int {
	if t == nil {
		return 0
	}
	return t.size
}

func (t *Transaction) GetDetails() *TransactionDetails {
	if t == nil {
		return nil
	}
	return t.details
}

type TxValidation int32

func (s *TxValidation) GetReason() string {
	if s == nil || int32(*s) < 0 {
		return "n/a"
	}
	if reason, ok := fabricpeer.TxValidationCode_name[int32(*s)]; !ok {
		return fmt.Sprintf("invalid code [%d]", s)
	} else {
		return reason
	}
}

func (s *TxValidation) Valid() bool {
	return s.GetReason() == "VALID"
}

func NewBlock(blk *cb.Block) (*Block, error) {
	if blk == nil {
		return nil, fmt.Errorf("nil")
	}
	blockNum := blk.GetHeader().GetNumber()
	transactionsIn := blk.GetData().GetData()
	filterIn := blk.GetMetadata().Metadata[cb.BlockMetadataIndex_TRANSACTIONS_FILTER]
	blockHash := blk.GetHeader().GetDataHash()
	if blockHash == nil {
		return nil, fmt.Errorf("no data hash")
	}
	blockHashHex := hex.EncodeToString(blockHash)

	txs := make([]*Transaction, 0, len(blk.GetData().GetData()))

	validations := make([]TxValidation, 0, len(filterIn))

	retBlock := &Block{
		hash:     blockHashHex,
		blockNum: blockNum,
		size:     proto.Size(blk),
	}

	for i, buf := range blk.GetData().GetData() {
		if len(transactionsIn) == len(filterIn) {
			validations = append(validations, TxValidation(int32(filterIn[i])))
		}

		if tx, err := NewTransaction(buf); err != nil {
			return nil, fmt.Errorf("new tx: %w", err)
		} else {
			txs = append(txs, tx)
		}
	}

	retBlock.txValidations = validations
	retBlock.transactions = txs

	return retBlock, nil
}

type lutherEvent map[string]string

func (s *lutherEvent) GetName() string {
	if s == nil {
		return ""
	}
	value, exists := (*s)[LutherEventName]
	if !exists {
		return ""
	}
	return value
}

func (s *lutherEvent) GetRequestID() string {
	if s == nil {
		return ""
	}
	value, exists := (*s)[LutherEventRequestID]
	if !exists {
		return ""
	}
	return value
}

func (s *lutherEvent) GetTimestamp() string {
	if s == nil {
		return ""
	}
	value, exists := (*s)[LutherEventTxTimestamp]
	if !exists {
		return ""
	}
	return value
}

type Event struct {
	*fabricpeer.ChaincodeEvent
}

func (s *Event) GetPayload() []byte {
	if s == nil {
		return nil
	}
	return s.Payload
}

func (s *Event) GetChaincodeId() string {
	if s == nil {
		return ""
	}
	return s.ChaincodeId
}

func (s *Event) IsLutherEvent() bool {
	if s == nil {
		return false
	}
	return s.GetEventName() == LutherEventKey
}

func (s *Event) String() string {
	if !s.IsLutherEvent() {
		return "<none>"
	}
	if lutherEvent, err := s.ToLutherEvent(); err != nil {
		return "<corrupt>"
	} else {
		return fmt.Sprintf("%s@%s [%s: %s]", lutherEvent.GetName(), lutherEvent.GetTimestamp(), lutherEvent.GetRequestID(), lutherEvent.getConnectorEventHeaders())
	}
}

func (s *Event) ToLutherEvent() (*lutherEvent, error) {
	if !s.IsLutherEvent() {
		return nil, fmt.Errorf("non-luther event")
	}
	if len(s.GetPayload()) == 0 {
		return nil, fmt.Errorf("missing luther event payload")
	}
	lEvent := &lutherEvent{}
	if err := json.Unmarshal(s.GetPayload(), lEvent); err != nil {
		return nil, err
	}
	return lEvent, nil
}

type Version struct {
	BlockNum uint64
	TxNum    uint64
}

func (s *Version) String() string {
	return fmt.Sprintf("(%d:%d)", s.BlockNum, s.TxNum)
}

type RSetRecord struct {
	Version *Version
	Key     string
}

func (s *RSetRecord) GetKey() string {
	if s == nil {
		return ""
	}
	return s.Key
}

func (s *RSetRecord) GetVersion() *Version {
	if s == nil {
		return nil
	}
	return s.Version
}

type PrivRSetRecord struct {
	Version *Version
	KeyHash []byte
}

func (s *PrivRSetRecord) GetKeyHash() []byte {
	if s == nil {
		return nil
	}
	return s.KeyHash
}

func (s *PrivRSetRecord) GetVersion() *Version {
	if s == nil {
		return nil
	}
	return s.Version
}

type WSetRecord struct {
	Key string
	Val []byte
}

func (s *WSetRecord) GetKey() string {
	if s == nil {
		return ""
	}
	return s.Key
}

func (s *WSetRecord) GetVal() []byte {
	if s == nil {
		return nil
	}
	return s.Val
}

type PrivWSetRecord struct {
	KeyHash []byte
	ValHash []byte
}

func (s *PrivWSetRecord) GetKeyHash() []byte {
	if s == nil {
		return nil
	}
	return s.KeyHash
}

func (s *PrivWSetRecord) GetVaHashl() []byte {
	if s == nil {
		return nil
	}
	return s.ValHash
}

type PvtRWSet struct {
	CollectionName string
	HashedReadSet  []*PrivRSetRecord
	HashedWriteSet []*PrivWSetRecord
}

func (s *PvtRWSet) GetCollectionName() string {
	if s == nil {
		return ""
	}
	return s.CollectionName
}

func (s *PvtRWSet) GetHashedWriteSet() []*PrivWSetRecord {
	if s == nil {
		return nil
	}
	return s.HashedWriteSet
}

func (s *PvtRWSet) GetHashedReadSet() []*PrivRSetRecord {
	if s == nil {
		return nil
	}
	return s.HashedReadSet
}

type RWSet struct {
	ReadSet  []*RSetRecord
	WriteSet []*WSetRecord
}

func (s *RWSet) GetWriteSet() []*WSetRecord {
	if s == nil {
		return nil
	}
	return s.WriteSet
}

func (s *RWSet) GetReadSet() []*RSetRecord {
	if s == nil {
		return nil
	}
	return s.ReadSet
}

type NSRWSet struct {
	RWSet     *RWSet
	Namespace string
}

func (s *NSRWSet) GetNamespace() string {
	if s == nil {
		return ""
	}
	return s.Namespace
}

func (s *NSRWSet) GetReadWriteSet() *RWSet {
	if s == nil {
		return nil
	}
	return s.RWSet
}

func getRWSet(rwSetBytes []byte) (*RWSet, error) {
	rwSet, err := protoutil.UnmarshalKVRWSet(rwSetBytes)
	if err != nil {
		return nil, err
	}
	rwSetExtracted := &RWSet{
		ReadSet:  []*RSetRecord{},
		WriteSet: []*WSetRecord{},
	}
	for _, read := range rwSet.GetReads() {
		rwSetExtracted.ReadSet = append(rwSetExtracted.GetReadSet(), &RSetRecord{
			Key: read.GetKey(),
			Version: &Version{
				BlockNum: read.GetVersion().GetBlockNum(),
				TxNum:    read.GetVersion().GetTxNum(),
			},
		})
	}
	for _, write := range rwSet.GetWrites() {
		rwSetExtracted.WriteSet = append(rwSetExtracted.GetWriteSet(), &WSetRecord{
			Key: write.GetKey(),
			Val: write.GetValue(),
		})
	}

	return rwSetExtracted, nil
}

func getNSRWSets(results []byte) ([]*NSRWSet, error) {
	if len(results) == 0 {
		return nil, nil
	}
	txRwSet, err := protoutil.UnmarshalTxReadWriteSet(results)
	if err != nil {
		return nil, fmt.Errorf("unmarshal TxReadWriteSet: %w", err)
	}

	nsRWSets := make([]*NSRWSet, 0, len(txRwSet.GetNsRwset()))

	for _, txrw := range txRwSet.GetNsRwset() {
		rwSetExtracted, err := getRWSet(txrw.GetRwset())
		if err != nil {
			return nil, fmt.Errorf("getRWSet: %w", err)
		}

		nsRWSets = append(nsRWSets, &NSRWSet{
			Namespace: txrw.GetNamespace(),
			RWSet:     rwSetExtracted,
		})
	}

	return nsRWSets, nil
}

func getAction(txBytes []byte) (*fabricpeer.ChaincodeAction, error) {
	if len(txBytes) == 0 {
		return nil, nil
	}
	tx, err := protoutil.UnmarshalTransaction(txBytes)
	if err != nil {
		return nil, err
	}

	actions := tx.GetActions()
	if len(actions) == 0 {
		return nil, nil
	}

	action := actions[0]

	actionPayloadBytes := action.GetPayload()
	if len(actionPayloadBytes) == 0 {
		return nil, nil
	}

	chaincodeActionPayload, err := protoutil.UnmarshalChaincodeActionPayload(actionPayloadBytes)
	if err != nil {
		return nil, err
	}

	proposalResponsePayloadBytes := chaincodeActionPayload.GetAction().GetProposalResponsePayload()
	if len(proposalResponsePayloadBytes) == 0 {
		return nil, nil
	}

	proposalResponse, err := protoutil.UnmarshalProposalResponsePayload(proposalResponsePayloadBytes)
	if err != nil {
		return nil, fmt.Errorf("invalid proposal response: %w", err)
	}

	chaincodeAction, err := protoutil.UnmarshalChaincodeAction(proposalResponse.GetExtension())
	if err != nil {
		return nil, err
	}

	return chaincodeAction, nil
}

func getEvent(eventBytes []byte) (*Event, error) {
	if len(eventBytes) == 0 {
		return nil, nil
	}
	event, err := protoutil.UnmarshalChaincodeEvents(eventBytes)
	if err != nil {
		return nil, err
	}

	return &Event{event}, nil
}

type TransactionDetails struct {
	event    *Event
	nsRWSets []*NSRWSet
}

func (s *TransactionDetails) GetEvent() *Event {
	if s == nil {
		return nil
	}
	return s.event
}

func (s *TransactionDetails) GetNamespaceReadWriteSet() []*NSRWSet {
	if s == nil {
		return nil
	}
	return s.nsRWSets
}

func (s *TransactionDetails) GetReadSetSize() int64 {
	var size int64
	for _, rwset := range s.GetNamespaceReadWriteSet() {
		for _, rset := range rwset.GetReadWriteSet().GetReadSet() {
			size += int64(len(rset.GetKey()))
		}
	}
	return size
}

func (s *TransactionDetails) GetWriteSetSize() int64 {
	var size int64
	for _, rwset := range s.GetNamespaceReadWriteSet() {
		for _, wset := range rwset.GetReadWriteSet().GetWriteSet() {
			size += int64(len(wset.GetKey())) + int64(len(wset.GetVal()))
		}
	}
	return size
}

func (s *TransactionDetails) GetWriteSetValue(ns string, key string) ([]byte, error) {
	if ns == "" {
		return nil, fmt.Errorf("missing namespace")
	}
	if key == "" {
		return nil, fmt.Errorf("missing key")
	}

	for _, rwset := range s.GetNamespaceReadWriteSet() {
		if rwset.GetNamespace() != ns {
			continue
		}
		for _, wset := range rwset.GetReadWriteSet().GetWriteSet() {
			if wset.GetKey() == key {
				return wset.GetVal(), nil
			}
		}
	}

	return nil, fmt.Errorf("key not found [%s]", key)
}

// GetPvtWriteSetValue looks up the value for a key stored in a PDC write set.
func GetPvtWriteSetValue(ns string, pdc string, key string, pvtData *rwset.TxPvtReadWriteSet) ([]byte, error) {
	if ns == "" {
		return nil, fmt.Errorf("missing namespace")
	}
	if key == "" {
		return nil, fmt.Errorf("missing key")
	}
	if pdc == "" {
		return nil, fmt.Errorf("missing PDC")
	}

	for _, pvtRwSet := range pvtData.GetNsPvtRwset() {
		if pvtRwSet.GetNamespace() != ns {
			continue
		}
		for _, collection := range pvtRwSet.GetCollectionPvtRwset() {
			if collection.GetCollectionName() != pdc {
				continue
			}
			rwSet, err := getRWSet(collection.GetRwset())
			if err != nil {
				return nil, err
			}
			for _, wset := range rwSet.GetWriteSet() {
				if wset.GetKey() == key {
					return wset.GetVal(), nil
				}
			}
		}
	}

	return nil, fmt.Errorf("key not found in private collection [%s:%s]", pdc, key)
}

// NewTransactionDetails converts proto bytes for a tx into a helper struct.
func NewTransactionDetails(txBytes []byte) (*TransactionDetails, error) {
	chaincodeAction, err := getAction(txBytes)
	if err != nil {
		return nil, fmt.Errorf("get action: %w", err)
	}

	details := &TransactionDetails{}

	if event, err := getEvent(chaincodeAction.GetEvents()); err != nil {
		return nil, fmt.Errorf("get event: %w", err)
	} else {
		details.event = event
	}

	if nsRWSets, err := getNSRWSets(chaincodeAction.GetResults()); err != nil {
		return nil, fmt.Errorf("get NSRWSets: %w", err)
	} else {
		details.nsRWSets = nsRWSets
	}

	return details, nil
}

func getPayload(envelopeBytes []byte) (*cb.Payload, error) {
	if len(envelopeBytes) == 0 {
		return nil, fmt.Errorf("empty envelope")
	}

	envelope, err := protoutil.UnmarshalEnvelope(envelopeBytes)
	if err != nil {
		return nil, err
	}

	payload, err := protoutil.UnmarshalPayload(envelope.GetPayload())
	if err != nil {
		return nil, err
	}

	return payload, nil
}

func getTransactionID(chanHeaderBytes []byte) (TransactionID, error) {
	channelheader, err := protoutil.UnmarshalChannelHeader(chanHeaderBytes)
	if err != nil {
		return "", err
	} else {
		return TransactionID(channelheader.GetTxId()), nil
	}
}

// NewTransaction creates an immutable transaction object.
func NewTransaction(envelopeBytes []byte) (*Transaction, error) {
	retTx := &Transaction{
		size: len(envelopeBytes),
	}

	payload, err := getPayload(envelopeBytes)
	if err != nil {
		return nil, fmt.Errorf("get payload: %w", err)
	}

	txID, err := getTransactionID(payload.GetHeader().GetChannelHeader())
	if err != nil {
		return nil, fmt.Errorf("get transaction ID: %w", err)
	}

	retTx.id = txID

	if details, err := NewTransactionDetails(payload.GetData()); err != nil {
		return nil, fmt.Errorf("transaction details: %w", err)
	} else {
		retTx.details = details
	}

	return retTx, nil
}

// ConnectorEventHeader captures metadata about a request.
type ConnectorEventHeader struct {
	RequestID string `json:"rid"`
}

func (s *ConnectorEventHeader) String() string {
	if s == nil {
		return ""
	}
	return fmt.Sprintf("{rid: %s}", s.RequestID)
}

type connectorEventHeaders []ConnectorEventHeader

func join(elems []string, sep string) string {
	switch len(elems) {
	case 0:
		return ""
	case 1:
		return elems[0]
	}
	n := len(sep) * (len(elems) - 1)
	for i := 0; i < len(elems); i++ {
		n += len(elems[i])
	}

	b := make([]byte, n)
	bp := copy(b, elems[0])
	for _, s := range elems[1:] {
		bp += copy(b[bp:], sep)
		bp += copy(b[bp:], s)
	}
	return string(b)
}

func (s connectorEventHeaders) String() string { // Changed receiver to non-pointer type
	events := make([]string, len(s))
	for i, event := range s {
		events[i] = event.String()
	}
	return fmt.Sprintf("[%s]", join(events, ", "))
}

func (s *lutherEvent) getConnectorEventHeaders() connectorEventHeaders {
	if s == nil {
		return nil
	}

	var events []ConnectorEventHeader

	for i := 0; i <= MaxConnectorEventsPerTx; i++ {
		eventKey := fmt.Sprintf("%s%d", LutherConnectorEventPrefix, i)
		value, exists := (*s)[eventKey]
		if !exists {
			return events
		}

		event := ConnectorEventHeader{}
		if err := json.Unmarshal([]byte(value), &event); err != nil {
			logrus.WithError(err).Error("invalid event format, ignoring...")
		} else {
			events = append(events, event)
		}
	}

	logrus.Warn("too many events")

	return events
}

// CallbackState wraps a context.
type CallbackState struct {
	Context ConnectorEventContext `json:"ctx"`
}

// ConnetorEventContext stores the context of the request.
type ConnectorEventContext struct {
	ObjectID       string `json:"oid"`
	RequestMSPID   string `json:"msp"`
	RequestKey     string `json:"key"`
	RequestPDC     string `json:"pdc"`
	RequestSystem  string `json:"sys"`
	RequestEnglish string `json:"eng"`
}

func (s *ConnectorEventContext) String() string {
	if s == nil {
		return "nil"
	}
	return fmt.Sprintf("{ oid: %s, msp: %s, key: %s, pdc: %s", s.ObjectID, s.RequestMSPID, s.RequestKey, s.RequestPDC)
}

// Valid determines if the event contect has the minimum set of fields
// to proceed with processing.
func (s *ConnectorEventContext) Valid() error {
	if s == nil {
		return fmt.Errorf("nil context")
	}
	if s.RequestKey == "" {
		return fmt.Errorf("missing request key")
	}
	return nil
}

// Event models an on-chain event.
type ConnectorEvent struct {
	unmarshalError error // TODO: not currently implemented
	context        ConnectorEventContext
	header         ConnectorEventHeader
	requestBody    json.RawMessage
}

// UnmarshalError returns an error encountered while extracting the particular
// connector event. This allows the caller to handle errors at the individual
// request level.
func (s *ConnectorEvent) UnmarshalError() error {
	if s == nil {
		return fmt.Errorf("nil event")
	}
	return s.unmarshalError
}

// RequestBody returns a copy of the request.
func (s *ConnectorEvent) RequestBody() json.RawMessage {
	if s == nil {
		return nil
	}
	reqCopy := make([]byte, len(s.requestBody))
	copy(reqCopy, s.requestBody)
	return reqCopy
}

// RequestID returns the ID of the request within the connector event.
func (s *ConnectorEvent) RequestID() string {
	if s == nil {
		return ""
	}
	return s.header.RequestID
}

// RequestMSPID the ID of the MSP meant to process this event.
func (s *ConnectorEvent) RequestMSPID() string {
	if s == nil {
		return ""
	}
	return s.context.RequestMSPID
}

// RequestSystem is the system name for the request.
func (s *ConnectorEvent) RequestSystem() string {
	if s == nil {
		return ""
	}
	return s.context.RequestSystem
}

// RequestEnglish is the english description for the request.
func (s *ConnectorEvent) RequestEnglish() string {
	if s == nil {
		return ""
	}
	return s.context.RequestEnglish
}

// ObjectID is the ID of the object that triggered the request.
func (s *ConnectorEvent) ObjectID() string {
	if s == nil {
		return ""
	}
	return s.context.ObjectID
}

func getConnectorEventContext(ns string, reqID string, pvtData *rwset.TxPvtReadWriteSet) (*ConnectorEventContext, error) {
	callbackState := &CallbackState{}
	if b, err := GetPvtWriteSetValue(ns, LutherConnectorEventContextPDC, fmt.Sprintf("%s%s", LutherConnectorEventContextPrefix, reqID), pvtData); err != nil {
		return nil, fmt.Errorf("missing event context: %w", err)
	} else if err := json.Unmarshal(b, callbackState); err != nil {
		return nil, fmt.Errorf("unmarshal context: %w", err)
	} else {
		return &callbackState.Context, nil
	}
}

func getConnectorEvent(ns string, header ConnectorEventHeader, tx *Transaction, pvtData *rwset.TxPvtReadWriteSet) (*ConnectorEvent, error) {
	reqID := header.RequestID
	eventCtx, err := getConnectorEventContext(ns, reqID, pvtData)
	if err != nil {
		return nil, fmt.Errorf("connector event context: %w", err)
	}

	logrus.WithFields(logrus.Fields{
		"req_id": reqID,
		"ns":     ns,
	}).Debugf("event context: [%s]", eventCtx)

	if err := eventCtx.Valid(); err != nil {
		return nil, fmt.Errorf("invalid event context: %w", err)
	}

	event := &ConnectorEvent{
		header:  header,
		context: *eventCtx,
	}

	var req []byte
	if eventCtx.RequestPDC != "" {
		req, err = GetPvtWriteSetValue(ns, eventCtx.RequestPDC, eventCtx.RequestKey, pvtData)
	} else {
		req, err = tx.GetDetails().GetWriteSetValue(ns, eventCtx.RequestKey)
	}
	if err != nil {
		return nil, fmt.Errorf("request body: %w", err)
	}
	event.requestBody = req
	return event, nil
}

// ConnectorEventUnmarshaler unmarshals connector events within a block with
// private data.
type ConnectorEventUnmarshaler struct {
	// CCIDFilter selects which chaincode to retrieve events from.
	CCIDFilter string
	MSPFilter  string
}

// Unmarshal returns connector events.
func (s *ConnectorEventUnmarshaler) Unmarshal(blkPvt *fabricpeer.BlockAndPrivateData) ([]*ConnectorEvent, error) {
	if blkPvt == nil {
		return nil, nil
	}
	block, err := NewBlock(blkPvt.GetBlock())
	if err != nil {
		return nil, fmt.Errorf("new block: %w", err)
	}

	events := make([]*ConnectorEvent, 0, len(block.GetTransactions()))
	for txSeqNo, tx := range block.GetTransactions() {
		if !block.GetValidation(txSeqNo).Valid() {
			continue
		}
		chainEvent := tx.GetDetails().GetEvent()
		if !chainEvent.IsLutherEvent() {
			continue
		}

		ccID := chainEvent.GetChaincodeId()
		if ccID == "" {
			return nil, fmt.Errorf("missing chaincode ID")
		}
		if s.CCIDFilter != "" && ccID != s.CCIDFilter {
			logrus.Debugf("ignoring chaincode event from ccid: [%s], want: [%s]", ccID, s.CCIDFilter)
			continue
		}

		lutherEvent, err := chainEvent.ToLutherEvent()
		if err != nil {
			return nil, fmt.Errorf("invalid luther event: %w", err)
		}

		if len(lutherEvent.getConnectorEventHeaders()) == 0 {
			logrus.Debugf("ignoring chaincode event, no connector events")
			continue
		}

		var txPvtData *rwset.TxPvtReadWriteSet
		hasTxPvtData := false
		if len(blkPvt.GetPrivateDataMap()) > 0 {
			txPvtData, hasTxPvtData = blkPvt.GetPrivateDataMap()[uint64(txSeqNo)]
		}
		if !hasTxPvtData {
			return nil, fmt.Errorf("connector event missing private data")
		}

		for _, header := range lutherEvent.getConnectorEventHeaders() {
			event, err := getConnectorEvent(ccID, header, tx, txPvtData)
			if err != nil {
				return nil, fmt.Errorf("connector event: %w", err)
			}
			if s.MSPFilter != "" && event.context.RequestMSPID != "" && s.MSPFilter != event.context.RequestMSPID {
				logrus.Debugf("ignoring chaincode event for msp: [%s], want: [%s]", event.context.RequestMSPID, s.MSPFilter)
				continue
			}
			events = append(events, event)
		}
	}

	return events, nil
}
