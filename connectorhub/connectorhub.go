// Package connectorhub demonstrates usage of the events lib.
package main

// TODO: create shiroclient-sdk (or direct gateway) WithEventCallback
// TODO: persist last block height state
// TODO: reliability (e.g., "best effort" delivery to connector and back)
// TODO: connetor router logic (replace processRequest)
// test using: cd fabric && ./client.sh start '[{"request_id": "123"}]'

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/luthersystems/sandbox/connectorhub/internal/events"
	"github.com/sirupsen/logrus"
)

var gatewayCfg = &events.GatewayConfig{
	MSPID:                "Org1MSP",
	UserID:               "User1", // Admin
	OrgDomain:            "org1.luther.systems",
	CryptoConfigRootPath: "../fabric/crypto-config",
	PeerName:             "peer0",
	PeerEndpoint:         "dns:///localhost:7051",
	ChannelName:          "luther",
	ChaincodeID:          "sandbox",
}

const (
	startBlock     int = 1
	checkpointFile     = "/tmp/checkpoint.tmp"
)

// processRequest receives a request from the phylum, and returns a response, or error.
// TODO: route request to connector, and return connector response, instead of stub.
func processRequest(ctx context.Context, req json.RawMessage, reqErr error) (json.RawMessage, error) {
	logrus.WithContext(ctx).
		WithField("req", string(req)).
		WithError(reqErr).
		Info("processing phylum request")
	if reqErr != nil {
		return nil, fmt.Errorf("request had error: %w", reqErr)
	}

	type OKResp struct {
		Status string `json:"status"`
	}

	responseStub := OKResp{
		Status: "OK",
	}

	respJSON, err := json.Marshal(responseStub)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal response: %w", err)
	}
	logrus.WithContext(ctx).Info("returning stub OK response")

	return respJSON, nil
}

func main() {
	logrus.SetLevel(logrus.DebugLevel)

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())

	var gatewayOpts []events.Option
	if startBlock > 0 {
		gatewayOpts = append(gatewayOpts, events.WithStartBlock(uint64(startBlock)))
	}
	if checkpointFile != "" {
		gatewayOpts = append(gatewayOpts, events.WithCheckpointFile(checkpointFile))
	}
	logrus.WithContext(ctx).Info("connecting to gateway")

	stream, err := events.GatewayEvents(gatewayCfg, gatewayOpts...)
	if err != nil {
		panic(err)
	}

	go func() {
		<-sigs
		logrus.WithContext(ctx).Info("signal handler called")
		cancel()
		if err := stream.Done(); err != nil {
			panic(err)
		}
	}()

	go func() {
		logrus.WithContext(ctx).Info("listening for events")
		for {
			select {
			case event := <-stream.Listen():
				if event == nil {
					logrus.WithContext(ctx).Info("nil event, exiting...")
					return
				}
				req, err := event.RequestBody()
				if err != nil {
					logrus.WithContext(ctx).WithError(err).Error("event received with error")
				}
				resp, err := processRequest(ctx, req, err)
				if err := event.Callback(resp, err); err != nil {
					logrus.WithContext(ctx).WithError(err).Error("event callback failed")
				} else {
					logrus.WithContext(ctx).Info("callback successful")
				}
			case <-ctx.Done():
				logrus.WithContext(ctx).Info("event listener shutting down...")
				return
			}
		}
	}()

	<-ctx.Done()

	logrus.WithContext(ctx).Info("connectorhub exited!")
}
