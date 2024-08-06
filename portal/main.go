// Copyright © 2024 Luther Systems, Ltd. All right reserved.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"

	"github.com/alecthomas/kong"
	"github.com/sirupsen/logrus"
)

type baseCmd struct {
	ctx context.Context
}

type cli struct {
	Version versionCmd `cmd:"version" help:"Get the version"`
	Start   startCmd   `cmd:"start" help:"Start the portal"`
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

func init() {
	logrus.SetFormatter(&logrus.TextFormatter{
		DisableColors: true,
		FullTimestamp: true,
	})
}

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	setupInterruptHandler(cancel)

	cli := &cli{
		Version: versionCmd{baseCmd: baseCmd{ctx: ctx}},
		Start:   startCmd{baseCmd: baseCmd{ctx: ctx}},
	}

	kctx := kong.Parse(cli)
	err := kctx.Run()
	kctx.FatalIfErrorf(err)
}
