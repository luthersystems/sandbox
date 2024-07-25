// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package cmd

import (
	"bytes"
	"testing"

	"github.com/luthersystems/svc/oracle"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v2"
)

func pretty(cfg *oracle.Config) string {
	b, err := yaml.Marshal(cfg)
	if err != nil {
		panic(err)
	}
	return string(b)
}

func TestConfig(t *testing.T) {
	myViper.SetConfigType("yaml")
	expectCfg := &oracle.Config{
		Verbose:         true,
		EmulateCC:       true,
		ListenAddress:   "listen-address",
		PhylumPath:      "phylum-path",
		GatewayEndpoint: "gateway-endpoint",
		OTLPEndpoint:    "otlp-endpoint",
	}
	yamlExample := []byte(pretty(expectCfg))
	err := myViper.ReadConfig(bytes.NewBuffer(yamlExample))
	require.NoError(t, err)
	gotCfg := getConfig()
	require.Equal(t, expectCfg, gotCfg)
}
