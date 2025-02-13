package ceph

import (
	"bufio"
	"cubectl/util/kube"
	"cubectl/util/settings"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/pkg/errors"
)

const (
	CephConfPath = "/etc/ceph/ceph.conf"
	CephAdminKey = "/etc/ceph/ceph.client.admin.keyring"

	RadosGatewayPort = 8888
)

func GetRadosGatewayUrl() string {
	return fmt.Sprintf("http://%s:%d/", settings.GetControllerIp(), RadosGatewayPort)
}

func getRegexMatchedHosts(line string) []string {
	regex := regexp.MustCompile(`([\d\.]+:6789)`)
	matches := regex.FindAllStringSubmatch(line, -1)
	hosts := []string{}
	hostIP := settings.GetMgmtIfIp()

	for _, match := range matches {
		if !strings.Contains(match[1], hostIP) {
			continue
		}

		for _, m := range matches {
			hosts = append(hosts, m[1])
		}
		break
	}

	return hosts
}

func parseMonitorHosts(file *os.File) ([]string, error) {
	hosts := []string{}
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "mon host = ") {
			continue
		}

		hosts = append(
			hosts,
			getRegexMatchedHosts(line)...,
		)
	}

	err := scanner.Err()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to read file")
	}
	if len(hosts) == 0 {
		return nil, fmt.Errorf("no monitor hosts found in %s", CephConfPath)
	}

	return hosts, nil
}

func GetClusterID() (string, error) {
	file, err := os.Open(CephConfPath)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to open file")
	}
	defer file.Close()

	fsid := ""
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "fsid = ") {
			continue
		}

		fsid = strings.TrimSpace(strings.TrimPrefix(line, "fsid = "))
		break
	}

	err = scanner.Err()
	if err != nil {
		return "", errors.Wrapf(err, "Failed to read file")
	}

	return fsid, nil
}

func GenTolerationControlPlane() (string, error) {
	b, err := json.Marshal(kube.TolerationControlPlane)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to marshal toleration control plane")
	}

	return string(b), nil
}

func GenCsiConfig() ([]CsiCluster, error) {
	clusterID, err := GetClusterID()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to get cluster ID")
	}

	file, err := os.Open(CephConfPath)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to open file")
	}
	defer file.Close()

	monitorHosts, err := parseMonitorHosts(file)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to parse monitor hosts")
	}

	return []CsiCluster{
		{
			ClusterID: clusterID,
			Monitors:  monitorHosts,
		},
	}, nil
}

func getSecretValue(file *os.File) (string, error) {
	value := ""
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.Contains(line, "key =") {
			continue
		}

		strSlice := strings.Split(line, " = ")
		isKeyFormatOk := len(strSlice) >= 2
		if isKeyFormatOk {
			value = strSlice[1]
			break
		}
	}

	err := scanner.Err()
	if err != nil {
		return "", errors.Wrapf(err, "Failed to read file")
	}
	if value == "" {
		return "", fmt.Errorf("no key found in %s", CephAdminKey)
	}

	return value, nil
}

func GetAdminSecret() (*Secret, error) {
	file, err := os.Open(CephAdminKey)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to open file")
	}
	defer file.Close()

	value, err := getSecretValue(file)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to get secret value")
	}

	return &Secret{
		Create:   true,
		UserID:   "admin",
		UserKey:  value,
		AdminID:  "admin",
		AdminKey: value,
	}, nil
}

func GenCsiConfigString(csiType string) (string, error) {
	csiConfig, err := GenCsiConfig()
	if err != nil {
		return "", errors.Wrapf(err, "Failed to generate csi config")
	}
	if csiType == CsiFs {
		csiConfig[0].CephFS = CephFS{SubVolumeGroup: DefaultFsSubVolumeGroup}
	}

	b, err := json.Marshal(csiConfig)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to marshal csi config")
	}

	return string(b), nil
}

func GenAdminSecretString() (string, error) {
	secret, err := GetAdminSecret()
	if err != nil {
		return "", errors.Wrapf(err, "Failed to generate admin secret")
	}

	b, err := json.Marshal(secret)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to marshal admin secret")
	}

	return string(b), nil
}
