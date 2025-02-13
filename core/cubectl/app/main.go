package main

import (
	"cubectl/cmd"
	"os"
)

func main() {
	os.Exit(cmd.RootExecute())
}
