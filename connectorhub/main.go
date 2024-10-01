// Package connectorhub demonstrates usage of the events lib.
//
// Bring up the local network `make up` and start the service running:
//
//	go run . start
//
// The service will listen for events, retrieve the request, process the
// request using a stub, and return a stub response.
//
// You can trigger events using this script in `fabric/` dir:
//
// > cd fabric && ./client.sh create_claim '[{}]'
//
//	{
//	 "claim": {
//	   "claim_id": "9b195776-961e-4d2b-9820-efc421f8959a",
//	   "state": "CLAIM_STATE_NEW"
//	 }
//	}
//
// By default the service uses a file checkpointer, stored at
// `/tmp/checkpoint.tmp`. If you wipe your network make sure you also
// wipe your checkpoint file, otherwise the service gets stuck trying to
// fetch future blocks.
//
// NOTE: there's something not quite right with the shiroclient-gw
// notify and phylum version. When running ./client.sh if you get
// "Method not found", you can try running `make init`, or deleting
// build/phylum_version and running `make init`. If that still doesn't
// fix it, run `make down up`, wait a few seconds, and
// `cd fabric && make init` again.
package main

// TODO: persist last block height state
// TODO: reliability (e.g., "best effort" delivery to connector and back)
// TODO: connector router logic (replace processRequest)

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"

	"github.com/alecthomas/kong"
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

type baseCmd struct {
	ctx context.Context
}

type cli struct {
	Start g `cmd:"" help:"Start the connector hub"`
}

type g struct {
	baseCmd
	runSettings
}

type runSettings struct {
	CheckpointFile   string `short:"c" type:"path" help:"Path to checkpoint file" default:"/tmp/checkpoint.tmp" env:"CH_CHECKPOINT_FILE"`
	StartBlockNumber uint64 `short:"b" help:"Block to start playing events from" default:"1"`
	Verbose          bool   `short:"v" help:"Verbose logs" default:"false"`
	Step             bool   `short:"s" help:"Interactive mode to pause for user input before processing event" default:"false"`
}

func init() {
	logrus.SetFormatter(&logrus.TextFormatter{
		DisableColors: true,
		FullTimestamp: true,
	})
}

func setupInterruptHandler(cancel context.CancelFunc) {
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	go func() {
		for range c {
			fmt.Println("\nReceived an interrupt, stopping tasks...")
			cancel()
		}
	}()
}

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	setupInterruptHandler(cancel)

	cli := &cli{
		Start: g{baseCmd: baseCmd{ctx: ctx}},
	}

	kctx := kong.Parse(cli)
	err := kctx.Run()
	kctx.FatalIfErrorf(err)
}

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
	logrus.WithContext(ctx).Debug("returning stub OK response")

	return respJSON, nil
}

func waitForUser(ctx context.Context) error {
	logrus.WithContext(ctx).WithField("demo_log", true).Info("Press 'Enter' to continue (or Ctrl-C to abort)...")

	done := make(chan error)

	go func() {
		_, err := bufio.NewReader(os.Stdin).ReadBytes('\n')
		done <- err
		close(done)
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-done:
		return err
	}
}

func prettyPrintPlatformRequest(event *events.Event) {
	logrus.WithFields(logrus.Fields{
		"demo_log": true,
		"claim_id": event.ObjectID(),
	}).Infof("Platform sent request (%s) to the system [%s] via connector [%s]", event.RequestEnglish(), event.RequestSystem(), event.RequestMSPID())
}

func prettyPrintConnectorResponse(event *events.Event) {
	logrus.WithFields(logrus.Fields{
		"demo_log": true,
		"claim_id": event.ObjectID(),
	}).Infof("[%s] response (%s) is sent to Platform via connector [%s]", event.RequestSystem(), event.RequestEnglish(), event.RequestMSPID())
}

func (s *g) Run() error {
	if s.Verbose {
		logrus.SetLevel(logrus.DebugLevel)
	}

	ctx := s.ctx

	var gatewayOpts []events.Option
	if s.StartBlockNumber > 0 {
		gatewayOpts = append(gatewayOpts, events.WithStartBlock(uint64(s.StartBlockNumber)))
	}
	if s.CheckpointFile != "" {
		gatewayOpts = append(gatewayOpts, events.WithCheckpointFile(s.CheckpointFile))
	}
	logrus.WithContext(ctx).Debug("connecting to gateway")

	stream, err := events.GatewayEvents(gatewayCfg, gatewayOpts...)
	if err != nil {
		return fmt.Errorf("gateway events: %w", err)
	}

	ctx, cancel := context.WithCancel(s.ctx)

	go func() {
		logrus.WithContext(ctx).Info("listening for events")
		for {
			select {
			case event := <-stream.Listen():
				if event == nil {
					logrus.WithContext(ctx).Info("nil event (stale checkpoint file?), exiting...")
					return
				}
				req, err := event.RequestBody()
				if err != nil {
					logrus.WithContext(ctx).WithError(err).Error("event received with error")
				}

				if s.Step {
					prettyPrintPlatformRequest(event)
					if err := waitForUser(ctx); err != nil {
						return
					}
				}

				resp, err := processRequest(ctx, req, err)

				if s.Step {
					prettyPrintConnectorResponse(event)
					if err := waitForUser(ctx); err != nil {
						return
					}
				}

				if err := event.Callback(resp, err); err != nil {
					logrus.WithContext(ctx).WithError(err).Error("event callback failed")
				} else {
					logrus.WithContext(ctx).Debug("callback successful")
				}
			case <-ctx.Done():
				logrus.WithContext(ctx).Info("event listener shutting down...")
				return
			}
		}
	}()

	<-ctx.Done()
	logrus.WithContext(ctx).Info("signal handler called")
	cancel()
	if err := stream.Done(); err != nil {
		logrus.WithError(err).Debug("stream done")
	}

	logrus.WithContext(ctx).Info("connectorhub exited!")

	return nil
}
