package cmd

import (
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}

func init() {
	//logger, err := zap.NewDevelopmentConfig().Build()
	//if err != nil {
	//	panic(fmt.Sprintf("log init failed: %v", err))
	//}

	rootOpts.debug = true
	initLogger()
}
