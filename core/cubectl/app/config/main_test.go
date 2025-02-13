package config

import (
	"fmt"
	"os"
	"testing"

	"go.uber.org/zap"
)

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}

func testClean(t *testing.T, f func()) bool {
	if os.Getenv("CLEANUP") != "false" {
		t.Cleanup(f)
	}
	if os.Getenv("CLEANUP") == "true" {
		return true
	}
	f()

	return false
}

func init() {
	//logger, err := zap.NewDevelopmentConfig().Build()
	//if err != nil {
	//	panic(fmt.Sprintf("log init failed: %v", err))
	//}

	// config := zap.NewDevelopmentConfig()
	// config.EncoderConfig.TimeKey = "timestamp"
	// config.EncoderConfig.EncodeTime = zapcore.RFC3339TimeEncoder

	// if !rootOpts.stacktrace {
	// 	config.DisableCaller = true
	// 	config.DisableStacktrace = true
	// }

	// if rootOpts.debug {
	// 	config.Level = zap.NewAtomicLevelAt(zap.DebugLevel)
	// 	//config.Development = true
	// }

	logger, err := zap.NewDevelopmentConfig().Build()
	if err != nil {
		panic(fmt.Sprintf("log init failed: %v", err))
	}

	zap.ReplaceGlobals(logger)
}
