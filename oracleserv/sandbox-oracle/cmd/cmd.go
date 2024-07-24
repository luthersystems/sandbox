// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package cmd

import (
	"log"
	"os"
	"strings"

	portal "github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/oracle"
	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/oracle/oracle"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const (
	envPrefix     = "SANDBOX_ORACLE"
	defaultConfig = ".sandbox-oracle"
)

// config parameters
const (
	configListenAddress   = "listen-address"
	configVerbose         = "verbose"
	configEmulateCC       = "emulate-cc"
	configPhylumPath      = "phylum-path"
	configGatewayEndpoint = "gateway-endpoint"
	configOTLPEndpoint    = "otlp-endpoint"
)

var myViper = viper.New()

func getConfig() *oracle.Config {
	return &oracle.Config{
		ListenAddress:   myViper.GetString(configListenAddress),
		Verbose:         myViper.GetBool(configVerbose),
		EmulateCC:       myViper.GetBool(configEmulateCC),
		PhylumPath:      myViper.GetString(configPhylumPath),
		GatewayEndpoint: myViper.GetString(configGatewayEndpoint),
		OTLPEndpoint:    myViper.GetString(configOTLPEndpoint),
	}
}

// RootCmd is the entrypoint for the oracle.
var RootCmd = &cobra.Command{
	Use:   "sandbox-oracle",
	Short: "Sandbox oracle",
	Long: `
Sandbox oracle.
`,
	Run: func(cmd *cobra.Command, args []string) {
		err := portal.Run(getConfig())
		if err != nil {
			log.Printf("error: %v", err)
			os.Exit(1)
		}
	},
}

func bindViper(flag string) {
	err := myViper.BindPFlag(flag, RootCmd.PersistentFlags().Lookup(flag))
	if err != nil {
		panic(err)
	}
}

func intFlag(flag string, def int, desc string) {
	RootCmd.PersistentFlags().Int(flag, def, desc)
}

func float64Flag(flag string, def float64, desc string) {
	RootCmd.PersistentFlags().Float64(flag, def, desc)
}

func stringFlag(flag string, def string, desc string) {
	RootCmd.PersistentFlags().String(flag, def, desc)
}

func stringSliceFlag(flag string, def []string, desc string) {
	RootCmd.PersistentFlags().StringSlice(flag, def, desc)
}

func boolFlag(flag string, def bool, desc string) {
	RootCmd.PersistentFlags().Bool(flag, def, desc)
}

var cfgPath string

// Execute parses CLI options.
func Execute() {
	cobra.OnInitialize(initConfig)

	RootCmd.PersistentFlags().StringVar(&cfgPath, "config", "", "config file")

	// Define global flags relevant to all subcommands and bind them to
	// the viper configuration chaincode setttings:
	cfg := &oracle.Config{}
	cfg.SetDefaults()

	defaultConfig := cfg

	intArgs := []struct {
		flag string
		def  int
		desc string
	}{}
	float64Args := []struct {
		flag string
		def  float64
		desc string
	}{}
	stringArgs := []struct {
		flag string
		def  string
		desc string
	}{
		{configListenAddress, defaultConfig.ListenAddress, "Listen address"},
		// NOTE:  The default configPhylumPath does not have the version number
		// or build identifier substituted in because the path for the phylum
		// file with substitutions is non-deterministic.
		{configPhylumPath, defaultConfig.PhylumPath, "Phylum path for emulation"},
		{configGatewayEndpoint, defaultConfig.GatewayEndpoint, "Shiroclient gateway endpoint"},
		{configOTLPEndpoint, defaultConfig.OTLPEndpoint, "OTLP tracing endpoint"},
	}
	stringSliceArgs := []struct {
		flag string
		def  []string
		desc string
	}{}

	boolArgs := []struct {
		flag string
		def  bool
		desc string
	}{
		{configVerbose, defaultConfig.Verbose, "Enable verbose logging"},
		{configEmulateCC, defaultConfig.EmulateCC, "Emulate chaincode"},
	}
	for _, arg := range intArgs {
		intFlag(arg.flag, arg.def, arg.desc)
		bindViper(arg.flag)
	}
	for _, arg := range float64Args {
		float64Flag(arg.flag, arg.def, arg.desc)
		bindViper(arg.flag)
	}
	for _, arg := range stringArgs {
		stringFlag(arg.flag, arg.def, arg.desc)
		bindViper(arg.flag)
	}
	for _, arg := range stringSliceArgs {
		stringSliceFlag(arg.flag, arg.def, arg.desc)
		bindViper(arg.flag)
	}
	for _, arg := range boolArgs {
		boolFlag(arg.flag, arg.def, arg.desc)
		bindViper(arg.flag)
	}

	if err := RootCmd.Execute(); err != nil {
		log.Printf("command error: %v", err)
		os.Exit(-1)
	}
}

func initConfig() {
	myViper.SetConfigName(defaultConfig) // name of config file (without extension)
	myViper.AddConfigPath("$HOME")       // adding home directory as first search path
	myViper.SetEnvPrefix(envPrefix)
	myViper.AutomaticEnv() // read in environment variables that match
	replacer := strings.NewReplacer(".", "_", "-", "_")
	myViper.SetEnvKeyReplacer(replacer)

	// Override default configuration search locations with a configuration
	// file specified on the command line.
	if cfgPath != "" {
		myViper.SetConfigFile(cfgPath)
		err := myViper.ReadInConfig()
		if err == nil {
			log.Printf("Using config file: %s", myViper.ConfigFileUsed())
		} else {
			log.Printf("Could not read config file: %v", err)
			os.Exit(1)
		}
	}
}
