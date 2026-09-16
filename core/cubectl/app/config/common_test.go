package config

import (
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strings"
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

func TestBuildCertSANs(t *testing.T) {
	tests := []struct {
		name     string
		settings map[string]string
		expect   string
	}{
		{
			// An HA cluster is the case #1421 is about: AMQP clients reach every
			// control node directly, so all of them have to be in the SAN.
			name: "HA covers every control node",
			settings: map[string]string{
				"cubesys.role":          "control",
				"cubesys.ha":            "true",
				"cubesys.controller":    "sky",
				"cubesys.control.vip":   "10.32.10.140",
				"cubesys.control.addrs": "10.32.10.141,10.32.10.142,10.32.10.143",
				"cubesys.control.hosts": "sky141,sky142,sky143",
			},
			expect: "subjectAltName=DNS:localhost,DNS:cube-controller,DNS:sky," +
				"IP:127.0.0.1,IP:10.32.10.140,IP:10.32.10.141,IP:10.32.10.142,IP:10.32.10.143," +
				"DNS:sky141,DNS:sky142,DNS:sky143",
		},
		{
			// cubesys.control.addrs and .hosts are absent from settings.txt on a
			// non-HA node, and strings.Split("", ",") yields [""] rather than an
			// empty slice. Emitting those as bare "IP:" makes openssl reject the
			// whole extension, so a fresh install would fail to get a certificate.
			name: "non-HA emits no empty entry",
			settings: map[string]string{
				"cubesys.role":       "control-converged",
				"cubesys.ha":         "false",
				"cubesys.management": "eth0",
				"net.if.addr.eth0":   "10.32.150.1",
				"net.hostname":       "sky150",
			},
			expect: "subjectAltName=DNS:localhost,DNS:cube-controller,DNS:sky150," +
				"IP:127.0.0.1,IP:10.32.150.1",
		},
		{
			name: "empty members of the control group are skipped",
			settings: map[string]string{
				"cubesys.role":          "control",
				"cubesys.ha":            "true",
				"cubesys.controller":    "ctrl",
				"cubesys.control.vip":   "10.0.0.10",
				"cubesys.control.addrs": "10.0.0.1,,10.0.0.3",
				"cubesys.control.hosts": "c1,,c3",
			},
			expect: "subjectAltName=DNS:localhost,DNS:cube-controller,DNS:ctrl," +
				"IP:127.0.0.1,IP:10.0.0.10,IP:10.0.0.1,IP:10.0.0.3,DNS:c1,DNS:c3",
		},
		{
			name: "a node that is also the VIP is listed once",
			settings: map[string]string{
				"cubesys.role":          "control",
				"cubesys.ha":            "true",
				"cubesys.controller":    "ctrl",
				"cubesys.control.vip":   "10.0.0.1",
				"cubesys.control.addrs": "10.0.0.1,10.0.0.2",
				"cubesys.control.hosts": "ctrl,c2",
			},
			expect: "subjectAltName=DNS:localhost,DNS:cube-controller,DNS:ctrl," +
				"IP:127.0.0.1,IP:10.0.0.1,IP:10.0.0.2,DNS:c2",
		},
		{
			// A non-control node resolves the controller through cubesys.controller.ip
			// instead of the VIP. The control group is still listed, because the
			// branch keys off cubesys.ha alone - only the master control node ever
			// signs a certificate, so there is nothing to guard against here.
			name: "a non-control node resolves the controller",
			settings: map[string]string{
				"cubesys.role":          "compute",
				"cubesys.ha":            "true",
				"cubesys.controller":    "ctrl",
				"cubesys.controller.ip": "10.0.0.10",
				"cubesys.control.addrs": "10.0.0.1,10.0.0.2",
				"cubesys.control.hosts": "c1,c2",
			},
			expect: "subjectAltName=DNS:localhost,DNS:cube-controller,DNS:ctrl," +
				"IP:127.0.0.1,IP:10.0.0.10,IP:10.0.0.1,IP:10.0.0.2,DNS:c1,DNS:c2",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if err := cubeSettings.LoadMap(test.settings); err != nil {
				t.Fatal(err)
			}

			sans := buildCertSANs()
			assert.Equal(t, test.expect, sans)

			// openssl rejects the extension outright on a null value, so guard the
			// shape as well as the content.
			for _, entry := range strings.Split(strings.TrimPrefix(sans, "subjectAltName="), ",") {
				kind, value, found := strings.Cut(entry, ":")
				assert.True(t, found, "entry %q has no kind", entry)
				assert.Contains(t, []string{"DNS", "IP"}, kind)
				assert.NotEmpty(t, value, "entry %q has an empty value", entry)
			}
		})
	}
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
