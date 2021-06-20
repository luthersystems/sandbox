// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package cmd

import (
	"bytes"
	"reflect"
	"testing"

	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/oracle"
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
		PhylumVersion:   "phylum-version",
		PhylumPath:      "phylum-path",
		GatewayEndpoint: "gateway-endpoint",
	}
	var yamlExample = []byte(pretty(expectCfg))
	myViper.ReadConfig(bytes.NewBuffer(yamlExample))
	gotCfg := getConfig()
	if !reflect.DeepEqual(expectCfg, gotCfg) {
		t.Errorf("Unexpected config\n-- Got:\n%v\n-- Expected:\n%v\n", pretty(gotCfg), pretty(expectCfg))
	}
}
