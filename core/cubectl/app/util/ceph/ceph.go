package ceph

import (
	"bufio"
	"cubectl/util/kube"
	"cubectl/util/settings"
	"encoding/base64"
	"encoding/binary"
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

// getRegexMatchedHosts returns every v1 monitor endpoint on a "mon host = " line.
// It must not filter them against this node's management IP: monitors bind the
// storage network, so that comparison matched nothing on any cluster with a
// separate storage VLAN and left ceph-csi without monitors.
func getRegexMatchedHosts(line string) []string {
	regex := regexp.MustCompile(`([\d\.]+:6789)`)
	matches := regex.FindAllStringSubmatch(line, -1)
	hosts := []string{}

	for _, match := range matches {
		hosts = append(hosts, match[1])
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

// aes128MountKey re-encodes a CephX key as an AES-128 one: type 1, the same
// created stamp, the first 16 bytes of its secret. An AES-128 key comes back as is.
//
// cephcsi v3.13.1 ships mount.ceph from Ceph 19.2.1, whose secret buffer only
// fits an AES-128 key (MAX_RAW_SECRET_LEN, raised in 19.2.6), so every cephfs
// mount with an aes256k key fails with "secret is not valid base64". CubeCOS
// runs with auth none, so the kernel is handed the key but never checks it.
// Drop this once the bundled cephcsi carries Ceph 19.2.6 or later.
func aes128MountKey(key string) (string, error) {
	const header = 2 + 8 + 2 // type, created, secret length
	const aes128 = 1
	raw, err := base64.StdEncoding.DecodeString(key)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to decode the ceph key")
	}
	if len(raw) < header {
		return "", fmt.Errorf("ceph key is %d bytes, too short", len(raw))
	}
	secretLen := int(binary.LittleEndian.Uint16(raw[10:12]))
	if len(raw) != header+secretLen || secretLen < 16 {
		return "", fmt.Errorf("ceph key holds a %d-byte secret in %d bytes", secretLen, len(raw))
	}
	if binary.LittleEndian.Uint16(raw[0:2]) == aes128 && secretLen == 16 {
		return key, nil
	}

	out := make([]byte, header+16)
	binary.LittleEndian.PutUint16(out[0:2], aes128)
	copy(out[2:10], raw[2:10])
	binary.LittleEndian.PutUint16(out[10:12], 16)
	copy(out[header:], raw[header:header+16])
	return base64.StdEncoding.EncodeToString(out), nil
}

// GenCsiFsSecretString is the admin secret for the cephfs chart, with the key in
// the form its mount.ceph can read (see aes128MountKey).
func GenCsiFsSecretString() (string, error) {
	secret, err := GetAdminSecret()
	if err != nil {
		return "", errors.Wrapf(err, "Failed to generate admin secret")
	}

	key, err := aes128MountKey(secret.AdminKey)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to convert the admin key for cephfs mounts")
	}
	secret.UserKey = key
	secret.AdminKey = key

	b, err := json.Marshal(secret)
	if err != nil {
		return "", errors.Wrapf(err, "Failed to marshal cephfs secret")
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
