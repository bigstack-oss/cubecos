package config

import (
	"database/sql"
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

func TestTerraformModuleMysql(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	if testClean(t, func() {
		ns.CleanupContainers()
		os.RemoveAll(path.Dir(mysqlSockFile))
		os.Remove(terraformStateFile)
	}) {
		return
	}

	if _, err := ns.RunEtcdContainer(); err != nil {
		t.Fatal(err)
	}

	if _, err := runMysqlContainer(ns, ""); err != nil {
		t.Fatal(err)
	}

	// // Ignore error
	// if err := terraformInitBackend(); err != nil {
	// 	t.Log(err)
	// }

	testdb := "testdb"

	if err := terraformExec("apply", "mysql", "mysql_dbname="+testdb); err != nil {
		t.Fatal(err)
	}

	if db, err := sql.Open("mysql", fmt.Sprintf("%s:%s@tcp(%s:%d)/%s", testdb, "password", "localhost", mysqlPort, testdb)); err != nil {
		t.Fatal(err)
	} else {
		defer db.Close()

		if err := db.Ping(); err != nil {
			t.Fatal(err)
		}
	}

	t.Run("Main", func(t *testing.T) {
	})

	t.Run("StatePushPull", func(t *testing.T) {
		stateBefore, _, err := util.ExecShf("etcdctl-cube.sh get terraform-state/ --prefix --print-value-only | jq .resources")
		if err != nil {
			t.Fatal(err)
		}

		if err := terraformPullState(); err != nil {
			t.Fatal(err)
		}

		_, _, err = util.ExecCmd("etcdctl-cube.sh", "del", "terraform-state/", "--prefix")
		if err != nil {
			t.Fatal(err)
		}

		if err := terraformPushState(); err != nil {
			t.Fatal(err)
		}

		stateAfter, _, err := util.ExecShf("etcdctl-cube.sh get terraform-state/ --prefix --print-value-only | jq .resources")
		if err != nil {
			t.Fatal(err)
		}

		assert.Equal(t, stateBefore, stateAfter)
	})
}
