package config

import (
	"database/sql"
	"os"
	"path"
	"testing"

	"cubectl/util"
	cubeTesting "cubectl/util/testing"
)

func runK3sContainer(ns *cubeTesting.Namespace) (*cubeTesting.Container, error) {
	if err := k3sWriteRegistriesFile(); err != nil {
		return nil, err
	}

	c := ns.NewContainer("docker.io/rancher/k3s:v1.19.5-k3s2")
	if err := c.RunDetach(
		[]string{
			//"-p", fmt.Sprintf("%d:%d", k3sPort, k3sPort),
			"--net=host",
			"-v", path.Dir(k3sRegistriesFile) + ":" + path.Dir(k3sRegistriesFile),
			"--privileged",
			//"--cgroupns=private",
			//"--security-opt", "label=disable",
		},
		"server",
		"--snapshotter=native",
		"--disable=traefik",
	); err != nil {
		return nil, err
	}

	// if err := util.CheckService("localhost", k3sPort, 10); err != nil {
	// 	return nil, err
	// }

	// Wait for /etc/rancher/k3s/k3s.yaml
	if err := util.Retry(
		func() error {
			// if _, _, err := c.Exec(nil, "ls", k3sConfigFile); err != nil {
			// 	return err
			// }

			if _, err := os.Stat(k3sConfigFile); os.IsNotExist(err) {
				return err
			}

			return nil
		},
		10,
	); err != nil {
		return nil, err
	}

	return c, nil
}

func TestCreateK3sDbIfNotExist(t *testing.T) {
	//t.Parallel()

	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		ns.CleanupContainers()
		os.RemoveAll(path.Dir(mysqlSockFile))
	}
	testClean()
	t.Cleanup(testClean)

	if _, err := runMysqlContainer(ns, ""); err != nil {
		t.Fatal(err)
	}

	if err := createK3sDbIfNotExist("localhost"); err != nil {
		t.Fatal(err)
	}

	if db, err := sql.Open("mysql", getK3sMysqlDsn("localhost")); err != nil {
		t.Fatal(err)
	} else {
		defer db.Close()

		if err := db.Ping(); err != nil {
			t.Fatal(err)
		}
	}
}
