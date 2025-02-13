package cmd

import (
	"fmt"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"

	cubeSettings "cubectl/util/settings"
)

const progName = "cubectl"

type RootOpts struct {
	debug      bool
	stacktrace bool
}

type stackTracer interface {
	StackTrace() errors.StackTrace
}

var (
	rootOpts RootOpts
)

func initLogger() {
	/*
		if isStdout {
			log.SetOutput(os.Stdout)
		} else {
			logwriter, err := syslog.New(syslog.LOG_INFO, progName)
			if err != nil {
				log.Printf("Fail to init syslog output: %v\n", err)
			} else {
				log.SetOutput(logwriter)
			}

		}
	*/

	var config zap.Config
	if !rootOpts.debug {
		config = zap.NewProductionConfig()
		config.EncoderConfig.TimeKey = "timestamp"
		config.EncoderConfig.EncodeTime = zapcore.RFC3339TimeEncoder
	} else {
		config = zap.NewDevelopmentConfig()
		//config.Level = zap.NewAtomicLevelAt(zap.DebugLevel)
		//config.Development = true
	}

	if !rootOpts.stacktrace {
		config.DisableCaller = true
		config.DisableStacktrace = true
	}

	logger, err := config.Build()
	if err != nil {
		panic(fmt.Sprintf("log init failed: %v", err))
	}

	zap.ReplaceGlobals(logger)
}

var RootCmd = &cobra.Command{
	Use:           progName,
	Short:         "Cube cluster control",
	SilenceErrors: true,
	SilenceUsage:  true,
}

func RootExecute() int {
	if err := cubeSettings.Load(); err != nil {
		zap.L().Warn("Failed to read settings file", zap.Error(err))
	}

	if err := RootCmd.Execute(); err != nil {
		var fields []zap.Field
		if rootOpts.stacktrace {
			fields = append(fields, zap.String("errstack", fmt.Sprintf("%+v", err.(stackTracer).StackTrace())))
		}

		zap.L().Error(fmt.Sprintf("%v", err), fields...)
		return 1
	}

	return 0
}

func init() {
	initLogger()
	// Called when invoking command Execute() to config flags
	cobra.OnInitialize(initLogger)
	cobra.EnableCommandSorting = false
	RootCmd.PersistentFlags().BoolVarP(&rootOpts.debug, "debug", "d", false, "Enable debug logging")
	RootCmd.PersistentFlags().BoolVarP(&rootOpts.stacktrace, "stacktrace", "s", false, "Enable stacktrace")
}
