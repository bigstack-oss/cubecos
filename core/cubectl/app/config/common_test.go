package config

import (
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"testing"

	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
	cubeTesting "cubectl/util/testing"
)

func runMysqlContainer(ns *cubeTesting.Namespace, pod string) (*cubeTesting.Container, error) {
	os.MkdirAll(path.Dir(mysqlSockFile), 0755)

	runArgs := []string{
		"-v", path.Dir(mysqlSockFile) + ":" + path.Dir(mysqlSockFile),
		"-e", "MYSQL_ALLOW_EMPTY_PASSWORD=true",
	}

	if pod == "" {
		runArgs = append(runArgs,
			"-p", fmt.Sprintf("%d:%d", mysqlPort, mysqlPort),
		)
	} else {
		runArgs = append(runArgs,
			"--pod", pod,
		)
	}

	c := ns.NewContainer("docker.io/library/mariadb:10.3.27")
	if err := c.RunDetach(
		runArgs,
		"--socket="+mysqlSockFile,
	); err != nil {
		return nil, err
	}

	if pod == "" {
		if err := util.CheckService("localhost", mysqlPort, 10); err != nil {
			return nil, err
		}
	}

	return c, nil
}

func TestGetIfaceIP(t *testing.T) {
	t.Skip("Skipping testing because cni-podman0 might not present at first time")
	t.Parallel()

	testClean := func() {
	}
	testClean()
	t.Cleanup(testClean)

	ip, err := getIfaceIP("cni-podman0")
	if err != nil {
		t.Fatal(err)
	}

	assert.Equal(t, "10.188.0.1", ip)
}

func TestGenSelfSignCerts(t *testing.T) {
	testClean(t, func() {
		os.RemoveAll(certsDir)
	})

	if err := cubeSettings.LoadMap(
		map[string]string{
			"cubesys.controller.ip": "1.1.1.1",
		},
	); err != nil {
		t.Fatal(err)
	}

	if err := genSelfSignCerts(); err != nil {
		t.Fatal(err)
	} else {
		if out, outErr, err := util.ExecCmd("openssl", "x509", "-noout", "-ext", "subjectAltName", "-in", certFile); err != nil {
			t.Fatal(err, outErr)
		} else {
			assert.Contains(t, out, "1.1.1.1")
		}

		if b, err := ioutil.ReadFile(certKeyFile); err != nil {
			t.Fatal(err)
		} else {
			assert.Contains(t, string(b), "-----BEGIN CERTIFICATE-----")
			assert.Contains(t, string(b), "-----BEGIN PRIVATE KEY-----")
		}
	}
}
