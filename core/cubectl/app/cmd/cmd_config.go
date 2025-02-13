package cmd

import (
	"os"
	"os/exec"

	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"cubectl/config"
	cubeSettings "cubectl/util/settings"
)

const hexConfigPath = "/usr/sbin/hex_config"

func hexConfig(subcmd string, args ...string) int {
	newArgs := append([]string{subcmd}, args...)

	hexConfig := exec.Command(hexConfigPath, newArgs...)
	hexConfig.Stdout = os.Stdout
	hexConfig.Stderr = os.Stderr
	err := hexConfig.Run()
	if err != nil {
		zap.S().Infof("%v\n", err)
		os.Exit(1)
	}

	//out, err := hex_config.CombinedOutput()
	//if err != nil {
	//	zap.S().Infof("%v", err)
	//}
	//log.Println(string(out))

	return 0
}

func setupEtcd() error {
	zap.S().Debugf("Running Etcd")

	if _, err := os.Stat(revisionFile); os.IsNotExist(err) {
		// Already joined
		if err := runThisnodeStart(nil, []string{}); err != nil {
			return err
		}
	} else {
		// Not joined
		if cubeSettings.IsMasterControl() {
			zap.S().Debugf("Creating a new cluster")
			if err := runThisnodeNew(nil, []string{}); err != nil {
				return err
			}
		} else {
			zap.S().Debugf("Joining an existing cluster")
			if err := runThisnodeJoin(nil, []string{}); err != nil {
				return err
			}
		}
	}

	return nil
}

var cmdConfig = &cobra.Command{
	Use:   "config <subcommand>",
	Short: "Configure cluster",
}

func init() {
	RootCmd.AddCommand(cmdConfig)
	// Init config modules and commands
	config.InitConfigModules(cmdConfig)
}
