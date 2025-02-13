package config

import (
	"fmt"
	"os"

	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	hostsFile      = "/etc/hosts"
	hostsMarkStart = "# <CLUSTER-NODES-START>"
	hostsMarkEnd   = "# <CLUSTER-NODES-END>"
)

func commitHost() error {
	if cubeSettings.GetRole() == "undef" {
		return nil
	}

	zap.S().Debugf("Executing commitHost()")
	//zap.S().Debug(settings.V().GetString("hostname"))

	nodeMap, err := util.LoadClusterSettings()
	if err != nil {
		zap.L().Warn("Cluster settings not found")
	}

	var buf string
	buf += hostsMarkStart + "\n"

	buf += fmt.Sprintln(cubeSettings.GetControllerIp(), "cube-controller")
	if nodeMap != nil {
		for _, node := range *nodeMap {
			buf += fmt.Sprintln(node.IP.Management, node.Hostname)
		}
	}

	buf += hostsMarkEnd + "\n"

	if _, outErr, err := util.ExecShf("sed '/%s/,/%s/d' %s > %s", hostsMarkStart, hostsMarkEnd, hostsFile, hostsFile+".tmp"); err != nil {
		return fmt.Errorf("%s, %v", outErr, err)
	}

	f, err := os.OpenFile(hostsFile+".tmp", os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer f.Close()

	if _, err := f.WriteString(buf); err != nil {
		return err
	}
	f.Sync()

	zap.S().Debugf("Wrote tmp hosts file %s", hostsFile+".tmp")

	if _, _, err := util.ExecCmd("cp", "-f", hostsFile+".tmp", hostsFile); err != nil {
		return err
	}

	return nil
}

func resetHost() error {
	if _, outErr, err := util.ExecShf("sed '/%s/,/%s/d' %s > %s", hostsMarkStart, hostsMarkEnd, hostsFile, hostsFile+".tmp"); err != nil {
		return fmt.Errorf("%s, %v", outErr, err)
	}

	if _, _, err := util.ExecCmd("cp", "-f", hostsFile+".tmp", hostsFile); err != nil {
		return err
	}

	return nil
}

func init() {
	m := NewModule("host")
	m.commitFunc = commitHost
	m.resetFunc = resetHost
}
