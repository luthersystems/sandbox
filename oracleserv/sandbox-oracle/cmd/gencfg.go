// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v2"
)

func init() {
	RootCmd.AddCommand(gencfgCmd)
}

var gencfgCmd = &cobra.Command{
	Use:   "gencfg config.yaml",
	Short: "Generate a configuration file and print to stdout",
	Run: func(cmd *cobra.Command, args []string) {
		b, err := yaml.Marshal(getConfig())
		if err != nil {
			fmt.Println(err)
			os.Exit(-1)
		}
		fmt.Println(string(b))
	},
}
