// Package events is a library for retrieving events issued by Luther.
package events

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"os"
	"path"
	"sync"

	"github.com/hyperledger/fabric-gateway/pkg/client"
	"github.com/hyperledger/fabric-gateway/pkg/identity"
	rwset "github.com/hyperledger/fabric-protos-go-apiv2/ledger/rwset"
	"github.com/hyperledger/fabric-protos-go-apiv2/peer"
	"github.com/luthersystems/sandbox/connectorhub/internal/chaininfo"
	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

// GatewayConfig configures a fabric gateway.
type GatewayConfig struct {
	MSPID                string
	UserID               string
	OrgDomain            string
	CryptoConfigRootPath string
	PeerName             string
	PeerEndpoint         string
	ChannelName          string
}

func (c *GatewayConfig) valid() error {
	if c == nil {
		return fmt.Errorf("missing config")
	}
	if c.MSPID == "" {
		return fmt.Errorf("missing MSP ID")
	}
	if c.UserID == "" {
		return fmt.Errorf("missing User ID")
	}
	if c.OrgDomain == "" {
		return fmt.Errorf("missing org domain")
	}
	if c.CryptoConfigRootPath == "" {
		return fmt.Errorf("missing crypto config root path")
	}
	if ok, err := isDirReadable(c.CryptoConfigRootPath); err != nil {
		return fmt.Errorf("fail to check dir [%s] is readable: %w", c.CryptoConfigRootPath, err)
	} else if !ok {
		return fmt.Errorf("dir [%s] not readable", c.CryptoConfigRootPath)
	}
	if c.PeerName == "" {
		return fmt.Errorf("missing peer name")
	}
	if c.PeerEndpoint == "" {
		return fmt.Errorf("missing peer endpoint")
	}
	if c.ChannelName == "" {
		return fmt.Errorf("missing channel name")
	}

	return nil
}

func isDirReadable(dir string) (bool, error) {
	info, err := os.Stat(dir)
	if os.IsNotExist(err) {
		return false, fmt.Errorf("directory does not exist")
	}
	if err != nil {
		return false, fmt.Errorf("error stating directory: %v", err)
	}

	if !info.IsDir() {
		return false, fmt.Errorf("path is not a directory")
	}

	file, err := os.Open(dir)
	if err != nil {
		return false, fmt.Errorf("directory is not readable: %v", err)
	}
	defer file.Close()

	_, err = file.Readdir(1)
	if err != nil && err != io.EOF {
		return false, fmt.Errorf("directory is not readable: %v", err)
	}

	return true, nil
}

func (c *GatewayConfig) cryptoPath() string {
	return fmt.Sprintf("%s/peerOrganizations/%s", c.CryptoConfigRootPath, c.OrgDomain)
}

func (c *GatewayConfig) mspPath() string {
	return fmt.Sprintf("%s/users/%s@%s/msp", c.cryptoPath(), c.UserID, c.OrgDomain)
}

func (c *GatewayConfig) certPath() string {
	return fmt.Sprintf("%s/signcerts", c.mspPath())
}

func (c *GatewayConfig) keyPath() string {
	return fmt.Sprintf("%s/keystore", c.mspPath())
}

func (c *GatewayConfig) clientTLSPath() string {
	return fmt.Sprintf("%s/users/%s@%s/tls", c.cryptoPath(), c.UserID, c.OrgDomain)
}

func (c *GatewayConfig) clientTLSKeyPath() string {
	return fmt.Sprintf("%s/client.key", c.clientTLSPath())
}

func (c *GatewayConfig) clientTLSCertPath() string {
	return fmt.Sprintf("%s/client.crt", c.clientTLSPath())
}

func (c *GatewayConfig) clientTLSCACertPath() string {
	return fmt.Sprintf("%s/ca.crt", c.clientTLSPath())
}

func (c *GatewayConfig) gatewayPeer() string {
	return fmt.Sprintf("%s.%s", c.PeerName, c.OrgDomain)
}

func (c *GatewayConfig) serverTLSCertPath() string {
	return fmt.Sprintf("%s/peers/%s/tls/ca.crt", c.cryptoPath(), c.gatewayPeer())
}

func (c *GatewayConfig) newGrpcConnection() *grpc.ClientConn {
	certificatePEM, err := os.ReadFile(c.serverTLSCertPath())
	if err != nil {
		panic(fmt.Errorf("failed to read server TLS certifcate file: %w", err))
	}

	clientCertPEM, err := os.ReadFile(c.clientTLSCertPath())
	if err != nil {
		panic(fmt.Errorf("failed to read client TLS certificate file: %w", err))
	}

	clientKeyPEM, err := os.ReadFile(c.clientTLSKeyPath())
	if err != nil {
		panic(fmt.Errorf("failed to read client TLS key file: %w", err))
	}

	clientCACertPEM, err := os.ReadFile(c.clientTLSCACertPath())
	if err != nil {
		panic(fmt.Errorf("failed to read client TLS CA certificate file: %w", err))
	}

	clientCertificate, err := tls.X509KeyPair(clientCertPEM, clientKeyPEM)
	if err != nil {
		panic(fmt.Errorf("failed to load client certificate and key: %w", err))
	}

	certPool := x509.NewCertPool()
	certPool.AppendCertsFromPEM(certificatePEM)
	certPool.AppendCertsFromPEM(clientCACertPEM)

	tlsConfig := &tls.Config{
		MinVersion:         tls.VersionTLS12,
		Certificates:       []tls.Certificate{clientCertificate},
		RootCAs:            certPool,
		ServerName:         c.gatewayPeer(),
		InsecureSkipVerify: false,
	}

	transportCredentials := credentials.NewTLS(tlsConfig)

	connection, err := grpc.NewClient(c.PeerEndpoint, grpc.WithTransportCredentials(transportCredentials))
	if err != nil {
		panic(fmt.Errorf("failed to create gRPC connection: %w", err))
	}

	return connection
}

// newIdentity creates a client identity for this Gateway connection using an X.509 certificate.
func (c *GatewayConfig) newIdentity() (*identity.X509Identity, error) {
	certificatePEM, err := readFirstFile(c.certPath())
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate file: %w", err)
	}

	certificate, err := identity.CertificateFromPEM(certificatePEM)
	if err != nil {
		return nil, fmt.Errorf("certificate from pem: %w", err)
	}

	id, err := identity.NewX509Identity(c.MSPID, certificate)
	if err != nil {
		return nil, fmt.Errorf("new x509: %w", err)
	}

	return id, nil
}

// newSign creates a function that generates a digital signature from a message digest using a private key.
func (c *GatewayConfig) newSign() (identity.Sign, error) {
	privateKeyPEM, err := readFirstFile(c.keyPath())
	if err != nil {
		return nil, fmt.Errorf("failed to read private key file: %w", err)
	}

	privateKey, err := identity.PrivateKeyFromPEM(privateKeyPEM)
	if err != nil {
		return nil, fmt.Errorf("private key from pem: %w", err)
	}

	sign, err := identity.NewPrivateKeySign(privateKey)
	if err != nil {
		return nil, fmt.Errorf("private key sign: %w", err)
	}

	return sign, nil
}

func readFirstFile(dirPath string) ([]byte, error) {
	dir, err := os.Open(dirPath)
	if err != nil {
		return nil, err
	}

	fileNames, err := dir.Readdirnames(1)
	if err != nil {
		return nil, err
	}

	return os.ReadFile(path.Join(dirPath, fileNames[0]))
}

func hashCert(certFilePath string) ([]byte, error) {
	clientCertPEM, err := os.ReadFile(certFilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read client TLS certificate file: %w", err)
	}

	// Compute the SHA-256 hash of the client certificate
	block, _ := pem.Decode(clientCertPEM)
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM block containing the client certificate")
	}
	clientCert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse client certificate: %w", err)
	}

	clientCertHash := sha256.Sum256(clientCert.Raw)
	return clientCertHash[:], nil
}

type eventBus struct {
	clientConnection *grpc.ClientConn
	network          *client.Network
	gateway          *client.Gateway
	respCallback     func(json.RawMessage) error
}

// makeEventBus returns an event bus.
func makeEventBus(cfg *GatewayConfig, eventsCfg *eventsConfig) (*eventBus, error) {
	if err := cfg.valid(); err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}
	clientConnection := cfg.newGrpcConnection()

	id, err := cfg.newIdentity()
	if err != nil {
		return nil, fmt.Errorf("new identity: %w", err)
	}
	sign, err := cfg.newSign()
	if err != nil {
		return nil, fmt.Errorf("sign: %w", err)
	}

	clientTlsCertHash, err := hashCert(cfg.clientTLSCertPath())
	if err != nil {
		return nil, fmt.Errorf("hash cert: %w", err)
	}

	gateway, err := client.Connect(
		id,
		client.WithSign(sign),
		client.WithTLSClientCertificateHash(clientTlsCertHash), // required for mutual TLS
		client.WithClientConnection(clientConnection),
	)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}

	network := gateway.GetNetwork(cfg.ChannelName)
	return &eventBus{
		clientConnection: clientConnection,
		network:          network,
		gateway:          gateway,
		respCallback:     eventsCfg.callback,
	}, nil
}

// close frees resources for an event bus.
func (s *eventBus) close() error {
	if s == nil {
		return fmt.Errorf("nil eventbus")
	}
	var errs []error
	if s.gateway != nil {
		errs = append(errs, s.gateway.Close())
	}
	if s.clientConnection != nil {
		errs = append(errs, s.clientConnection.Close())
	}

	var retErr error
	for _, err := range errs {
		if err != nil {
			if retErr == nil {
				retErr = err
			} else {
				retErr = fmt.Errorf("%w: %w", retErr, err)
			}
		}
	}

	return retErr
}

func unmarshalLutherEvents(blkPvt *peer.BlockAndPrivateData) ([]*Event, error) {
	if blkPvt == nil {
		return nil, nil
	}
	block, err := chaininfo.NewBlock(blkPvt.GetBlock())
	if err != nil {
		return nil, fmt.Errorf("new block: %w", err)
	}

	blockNum := block.GetBlockNum()
	events := make([]*Event, 0, len(block.GetTransactions()))
	for txSeqNo, tx := range block.GetTransactions() {
		fmt.Printf("WTF: tx [%d]\n", txSeqNo)
		if !block.GetValidation(txSeqNo).Valid() {
			continue
		}
		fmt.Printf("WTF2: tx [%d]\n", txSeqNo)
		chainEvent := tx.GetDetails().GetEvent()
		if !chainEvent.IsLutherEvent() {
			continue
		}

		fmt.Printf("WTF3: tx [%d]\n", txSeqNo)
		ccID := chainEvent.GetChaincodeId()
		if ccID == "" {
			return nil, fmt.Errorf("missing chaincode ID")
		}

		fmt.Printf("WTF4: tx [%d:%s]\n", txSeqNo, ccID)
		lutherEvent, err := chainEvent.ToLutherEvent()
		if err != nil {
			return nil, fmt.Errorf("invalid luther event: %w", err)
		}

		var txPvtData *rwset.TxPvtReadWriteSet
		hasTxPvtData := false
		if len(blkPvt.GetPrivateDataMap()) > 0 {
			txPvtData, hasTxPvtData = blkPvt.GetPrivateDataMap()[uint64(txSeqNo)]
		}

		for _, connectorEvent := range lutherEvent.GetConnectorEvents() {
			var request json.RawMessage
			event := &Event{
				header: EventHeader{
					BlockNum:     blockNum,
					RequestID:    connectorEvent.RequestID,
					RequestKey:   connectorEvent.Key,
					RequestPDC:   connectorEvent.PDC,
					RequestMSPID: connectorEvent.MSPID,
				},
				request: request,
			}
			if err := event.header.valid(); err != nil {
				event.unmarshalError = err
			} else if connectorEvent.PDC != "" {
				if !hasTxPvtData {
					event.unmarshalError = fmt.Errorf("missing private data")
				} else if req, err := chaininfo.GetPvtWriteSetValue(ccID, connectorEvent.PDC, connectorEvent.Key, txPvtData); err != nil {
					event.unmarshalError = err
				} else {
					event.request = req
				}
			} else {
				if req, err := tx.GetDetails().GetWriteSetValue(ccID, connectorEvent.Key); err != nil {
					event.unmarshalError = err
				} else {
					event.request = req
				}
			}
			if len(event.request) == 0 && event.unmarshalError == nil {
				event.unmarshalError = fmt.Errorf("empty request")
			}

			events = append(events, event)
		}
	}

	return events, nil
}

// Events capture requests raised by phylum transactions.
type Event struct {
	unmarshalError error
	respCallback   func(json.RawMessage) error
	header         EventHeader
	request        json.RawMessage
	respCount      int
	callbackMutex  sync.Mutex
}

// EventHeader captures metadata about a request.
type EventHeader struct {
	RequestID    string
	RequestMSPID string
	RequestKey   string
	RequestPDC   string
	BlockNum     uint64
}

// valid determines if the header has all the required fields.
func (e *EventHeader) valid() error {
	if e == nil {
		return fmt.Errorf("event missing header")
	}
	if e.BlockNum == 0 {
		return fmt.Errorf("event missing block num")
	}
	if e.RequestID == "" {
		return fmt.Errorf("event missing request ID")
	}
	if e.RequestKey == "" {
		return fmt.Errorf("event missing request key")
	}

	return nil
}

// Header returns the metadata for the event.
func (e *Event) Header() EventHeader {
	if e == nil {
		return EventHeader{}
	}
	return e.header
}

// RequestBody returns the request, or an error if the request
// could not be retrieved.
func (e *Event) RequestBody() (json.RawMessage, error) {
	if e == nil {
		return nil, nil
	}
	if e.unmarshalError != nil {
		return nil, e.unmarshalError
	}
	return e.request, nil
}

func (e *Event) makeCallbackMessage(resp json.RawMessage, err error) (json.RawMessage, error) {
	type CallbackMessage struct {
		RequestID string          `json:"request_id"`
		Error     string          `json:"error,omitempty"`
		Response  json.RawMessage `json:"response,omitempty"`
	}

	var errMsg string
	if err != nil {
		errMsg = err.Error()
	}

	callbackMessage := CallbackMessage{
		RequestID: e.header.RequestID,
		Response:  resp,
		Error:     errMsg,
	}

	jsonData, err := json.Marshal(callbackMessage)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal callback message: %w", err)
	}

	return jsonData, nil
}

// Callback sends a response to the event back to Luther, or an error if
// processing failed.
func (e *Event) Callback(resp json.RawMessage, err error) error {
	logrus.Debug("callback triggered")
	if e == nil {
		return fmt.Errorf("nil event")
	}
	e.callbackMutex.Lock()
	defer e.callbackMutex.Unlock()

	if len(resp) == 0 && err == nil {
		return fmt.Errorf("missing response")
	}
	if len(resp) > 0 && err != nil {
		return fmt.Errorf("exactly one of resp or err required")
	}

	respRaw, err := e.makeCallbackMessage(resp, err)
	if err != nil {
		return fmt.Errorf("marshal callback: %w", err)
	}

	if e.respCallback != nil {
		logrus.Debug("passing event response to registered callback")
		err = e.respCallback(respRaw)
		if err != nil {
			return fmt.Errorf("callback: %w", err)
		}
	} else {
		logrus.WithField("resp", string(respRaw)).Debug("no registered callback, ignoring response")
	}
	e.respCount++

	return nil
}

// EventSteam provides a stream of events issued from Luther.
type EventStream struct {
	eventBus  *eventBus
	eventChan <-chan *Event
	cancel    context.CancelFunc
	done      chan struct{}
	wg        sync.WaitGroup
	once      sync.Once
}

// Listen returns a channel that receives events.
func (s *EventStream) Listen() <-chan *Event {
	if s == nil {
		return nil
	}

	return s.eventChan
}

// Done closes the event stream and blocks the caller until resources are freed.
// Subsequent calls to Done() are ignored.
func (s *EventStream) Done() error {
	logrus.Info("steam done")
	if s == nil {
		return nil
	}

	var err error
	s.once.Do(func() {
		logrus.Info("exiting event stream")
		close(s.done) // Signal the goroutine to stop
		s.cancel()
		s.wg.Wait()              // Wait for the goroutine to finish
		err = s.eventBus.close() // Clean up the event bus
		logrus.Info("event bus closed")
	})

	return err
}

type eventsConfig struct {
	callback   func(json.RawMessage) error
	startBlock uint64
}

// Option configures the event service.
type Option func(*eventsConfig)

// WithEventCallback configures a function that's responsible for processing
// event responses.
func WithEventCallback(callback func(json.RawMessage) error) Option {
	return func(cfg *eventsConfig) {
		cfg.callback = callback
	}
}

// WithStartBlock sets the initial block to start retrieving events from.
func WithStartBlock(blockNum uint64) Option {
	return func(cfg *eventsConfig) {
		cfg.startBlock = blockNum
	}
}

// GatewayEvents returns a channel that streams Luther events directly
// from a fabric gateway.
func GatewayEvents(cfg *GatewayConfig, opts ...Option) (*EventStream, error) {
	ctx := context.Background()

	eventsCfg := &eventsConfig{}
	for _, opt := range opts {
		opt(eventsCfg)
	}

	logrus.WithContext(ctx).Debug("make event bus")
	bus, err := makeEventBus(cfg, eventsCfg)
	if err != nil {
		return nil, fmt.Errorf("make event bus: %w", err)
	}

	events := make(chan *Event)
	ctx, cancel := context.WithCancel(ctx)
	stream := &EventStream{
		eventBus:  bus,
		eventChan: events,
		cancel:    cancel,
		done:      make(chan struct{}),
	}
	stream.wg.Add(1)

	var networkEventsOpt []client.BlockEventsOption
	if eventsCfg.startBlock > 0 {
		networkEventsOpt = append(networkEventsOpt, client.WithStartBlock(eventsCfg.startBlock))
	}

	logrus.WithContext(ctx).Debug("listen to fabric events")

	fabEvents, err := bus.network.BlockAndPrivateDataEvents(ctx, networkEventsOpt...)
	if err != nil {
		return nil, fmt.Errorf("failed to start block event listening: %w", err)
	}

	logrus.WithContext(ctx).Debug("kicking of go routine to process events")
	go func() {
		defer func() {
			close(events)
			stream.wg.Done()
			if err := bus.close(); err != nil {
				logrus.WithContext(ctx).WithError(err).Error("close")
			} else {
				logrus.WithContext(ctx).Debug("event hub closed")
			}
		}()
		for {
			logrus.WithContext(ctx).Debug("selecting on events")
			select {
			case event := <-fabEvents:
				if event == nil {
					logrus.WithContext(ctx).Info("nil event, exiting...")
					return
				}
				logrus.WithContext(ctx).WithField("block_no", event.GetBlock().GetHeader().GetNumber()).Debug("received event")
				lutherEvents, err := unmarshalLutherEvents(event)
				if err != nil {
					logrus.WithContext(ctx).WithError(err).Error("unmarshal luther event")
					continue
				}
				logrus.WithContext(ctx).
					WithField("num_events", len(lutherEvents)).
					Info("processing luther events")
				for _, event := range lutherEvents {
					if event.Header().RequestMSPID != "" && event.Header().RequestMSPID != cfg.MSPID {
						logrus.WithContext(ctx).WithFields(logrus.Fields{
							"req_msp": event.Header().RequestMSPID,
							"gw_msp":  cfg.MSPID,
						}).Debug("skipping event for other MSP")
						continue
					}
					event.respCallback = bus.respCallback
					events <- event
				}
				logrus.WithContext(ctx).
					Info("done processing luther events")
			case <-ctx.Done():
				return
			case <-stream.done:
				return
			}
		}
	}()

	return stream, nil
}