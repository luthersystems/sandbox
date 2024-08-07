// Copyright © 2024 Luther Systems, Ltd. All right reserved.
package main

import (
	"fmt"

	"github.com/luthersystems/sandbox/portal/version"
)

type versionCmd struct {
	baseCmd
}

func (r *versionCmd) Run() error {
	ver := version.Version
	if ver == "" {
		ver = "SNAPSHOT"
	}
	fmt.Println(ver)
	return nil
}
