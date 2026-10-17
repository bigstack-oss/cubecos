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

var k3sTestLadder = []string{"v1.27.16+k3s1", "v1.28.15+k3s1", "v1.29.15+k3s1", "v1.30.14+k3s2", "v1.31.14+k3s1"}

const k3sTestFinal = k3sDataDir + K3sBin

func k3sTestStep(v string) string {
	return k3sLadderDir + v + "/" + K3sBin
}

func TestK3sPickBinary_NotMigration_InstallsFinal(t *testing.T) {
	for _, rec := range []string{"", "v1.26.6+k3s1", "v1.30.14+k3s2"} {
		if got := k3sPickBinary(false, rec, k3sTestLadder); got != k3sTestFinal {
			t.Errorf("record %q: got %s, want %s", rec, got, k3sTestFinal)
		}
	}
}

func TestK3sPickBinary_NoRecord_TreatsAs1266(t *testing.T) {
	if got, want := k3sPickBinary(true, "", k3sTestLadder), k3sTestStep("v1.27.16+k3s1"); got != want {
		t.Errorf("got %s, want %s", got, want)
	}
}

func TestK3sPickBinary_Record130_InstallsNextMinor(t *testing.T) {
	if got, want := k3sPickBinary(true, "v1.30.14+k3s2", k3sTestLadder), k3sTestStep("v1.31.14+k3s1"); got != want {
		t.Errorf("got %s, want %s", got, want)
	}
}

func TestK3sPickBinary_RecordFinalMinus1_InstallsFinal(t *testing.T) {
	if got := k3sPickBinary(true, "v1.31.14+k3s1", k3sTestLadder); got != k3sTestFinal {
		t.Errorf("got %s, want %s", got, k3sTestFinal)
	}
}

func TestK3sPickBinary_RecordIsFinal_InstallsFinal(t *testing.T) {
	if got := k3sPickBinary(true, "v1.32.13+k3s1", k3sTestLadder); got != k3sTestFinal {
		t.Errorf("got %s, want %s", got, k3sTestFinal)
	}
}

func TestK3sPickBinary_GarbageRecord_TreatsAs1266(t *testing.T) {
	for _, rec := range []string{"foo", "v2", "1.30"} {
		if got, want := k3sPickBinary(true, rec, k3sTestLadder), k3sTestStep("v1.27.16+k3s1"); got != want {
			t.Errorf("record %q: got %s, want %s", rec, got, want)
		}
	}
}

func TestK3sIngressGate_AllFinal_True(t *testing.T) {
	if !k3sServersAt([]string{"v1.32.13+k3s1", "v1.32.13+k3s1"}, "v1.32.13+k3s1") {
		t.Error("got false, want true")
	}
}

func TestK3sIngressGate_MixedVersions_False(t *testing.T) {
	for _, vs := range [][]string{
		{"v1.32.13+k3s1", "v1.31.14+k3s1"},
		{"v1.27.16+k3s1", "v1.27.16+k3s1"},
		{},
	} {
		if k3sServersAt(vs, "v1.32.13+k3s1") {
			t.Errorf("%v: got true, want false", vs)
		}
	}
}

func TestK3sIngressGate_Upgrade(t *testing.T) {
	const old, cur = "ingress-nginx-4.7.1", "ingress-nginx-4.15.1"
	for _, c := range []struct {
		name                      string
		nsExists, force, migrated bool
		deployed                  string
		serversFinal, want        bool
	}{
		{"fresh install", false, false, false, "", false, true},
		{"force", true, true, false, cur, false, true},
		{"migration mid-ladder keeps the release", true, false, true, old, false, false},
		{"migration at the final k3s", true, false, true, old, true, true},
		{"ladder done, chart behind", true, false, false, old, true, true},
		{"chart behind, servers not final", true, false, false, old, false, false},
		{"nothing to do", true, false, false, cur, true, false},
	} {
		if got := k3sIngressShouldUpgrade(c.nsExists, c.force, c.migrated, c.deployed, cur, c.serversFinal); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}
