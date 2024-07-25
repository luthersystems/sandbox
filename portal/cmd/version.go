// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/luthersystems/sandbox/portal/version"
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
