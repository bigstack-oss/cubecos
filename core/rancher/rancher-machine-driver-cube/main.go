package main

import (
	"rancher-machine-driver-cube/cube"

	"github.com/rancher/machine/libmachine/drivers/plugin"
)

func main() {
	plugin.RegisterDriver(cube.NewDriver("", ""))
}
