package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/luthersystems/sandbox/oracleserv/sandbox-oracle/version"
)

func init() {
	RootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(version.Version)
	},
}
