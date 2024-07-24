// Copyright © 2024 Luther Systems, Ltd. All right reserved.

package oracle

import (
	"bytes"
	"fmt"
	"io"
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/require"
)

type testWriter struct {
	t *testing.T
	b *bytes.Buffer
}

func newTestWriter(t *testing.T) *testWriter {
	var b bytes.Buffer
	return &testWriter{t: t, b: &b}
}

func (tw testWriter) Write(p []byte) (n int, err error) {
	for _, b := range p {
		if b == '\n' {
			tw.t.Log(tw.b.String())
			tw.b.Reset()
			continue
		}
		// bytes.Buffer panics on error
		tw.b.WriteByte(b)
	}
	return n, nil
}

// Snapshot takes a snapshot of the current oracle.
func (orc *Oracle) Snapshot(t *testing.T) []byte {
	orc.stateMut.RLock()
	defer orc.stateMut.RUnlock()
	if orc.state != oracleStateTesting {
		panic(fmt.Errorf("snapshot: invalid oracle state: %d", orc.state))
	}

	var snapshot bytes.Buffer
	err := orc.phylum.MockSnapshot(&snapshot)
	require.NoError(t, err)
	return snapshot.Bytes()
}

// NewTestOracleFrom is used to create an oracle for testing, loading the
// state from an optional snapshot.
func NewTestOracleFrom(t *testing.T, snapshot []byte) (*Oracle, func()) {
	cfg := defaultConfig()
	cfg.Verbose = testing.Verbose()
	logger := logrus.New()
	logger.SetOutput(newTestWriter(t))
	var r io.Reader
	if snapshot != nil {
		r = bytes.NewReader(snapshot)
	}
	opts := []option{
		withLogBase(logger.WithFields(nil)),
		withMockPhylumFrom("../../../phylum", r),
	}
	server, err := newOracle(cfg, opts...)
	server.state = oracleStateTesting
	if err != nil {
		t.Fatal(err)
	}

	if cfg.Verbose {
		logger.SetLevel(logrus.DebugLevel)
	}

	orcStop := func() {
		err := server.close()
		require.NoError(t, err)
	}

	return server, orcStop
}
