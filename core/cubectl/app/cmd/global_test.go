package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
	cubeTesting "cubectl/util/testing"
)

var settingsFile = "/etc/settings.txt"

func RunEtcdContainer(ns *cubeTesting.Namespace) (*cubeTesting.Container, error) {
	c := ns.NewContainer("gcr.io/etcd-development/etcd:v3.5.5")
	if err := c.RunDetach(
		nil,
		"etcd",
		"--listen-client-urls=http://0.0.0.0:"+strconv.Itoa(etcdClientPort),
		"--advertise-client-urls=http://0.0.0.0:"+strconv.Itoa(etcdClientPort),
	); err != nil {
		return nil, err
	}

	return c, nil
}

func TestWriteEtcdConfig(t *testing.T) {
	t.Cleanup(func() {
		os.Remove(settingsFile)
		os.Remove(etcdConfigFile)
	})

	if err := cubeTesting.GenerateSettingsRaw(settingsFile, ""); err != nil {
		t.Fatal(err)
	} else {
		if err := cubeSettings.Load(); err != nil {
			t.Fatal(err)
		}
	}

	t.Run("NewCluserConfig", func(t *testing.T) {
		err := writeEtcdConfig("new", "")
		if err != nil {
			t.Fatal(err)
		}

		viper.SetConfigType("yaml")
		viper.SetConfigFile(etcdConfigFile)
		if err := viper.ReadInConfig(); err != nil {
			t.Fatal(err)
		}

		assert.Equal(t, "new", viper.GetString("initial-cluster-state"))
		assert.Equal(t, "", viper.GetString("initial-cluster"))
	})

	t.Run("ExistingCluserConfig", func(t *testing.T) {
		testInitialCluster := fmt.Sprintf("s1=http://1.1.1.1:%d,s2=http://2.2.2.2:%d", etcdPeerPort, etcdPeerPort)

		err := writeEtcdConfig("existing", testInitialCluster)
		if err != nil {
			t.Fatal(err)
		}

		viper.SetConfigType("yaml")
		viper.SetConfigFile(etcdConfigFile)
		if err := viper.ReadInConfig(); err != nil {
			t.Fatal(err)
		}

		assert.Equal(t, "existing", viper.GetString("initial-cluster-state"))
		assert.Equal(t, testInitialCluster, viper.GetString("initial-cluster"))
	})
}

func TestEtcdMemberAddPromote(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	teardown := func() {
		os.Remove(settingsFile)
		os.Remove(etcdConfigFile)
		ns.CleanupContainers()
	}

	t.Cleanup(teardown)
	teardown()

	// Generate empty /etc/settings.txt
	if err := cubeTesting.GenerateSettingsRaw(settingsFile, ""); err != nil {
		t.Fatal(err)
	} else {
		if err := cubeSettings.Load(); err != nil {
			t.Fatal(err)
		}
	}

	node1Name := "node1"
	node1Ip := "10.188.2.51"
	node1CmdArgs := []string{
		"etcd",
		"--name=" + node1Name,
		"--listen-client-urls=http://0.0.0.0:" + strconv.Itoa(etcdClientPort),
		"--advertise-client-urls=http://0.0.0.0:" + strconv.Itoa(etcdClientPort),
		"--listen-peer-urls=http://0.0.0.0:" + strconv.Itoa(etcdPeerPort),
		"--initial-advertise-peer-urls=http://" + node1Ip + ":" + strconv.Itoa(etcdPeerPort),
		"--initial-cluster-token=cube",
		"--initial-cluster-state=new",
	}

	node1 := ns.NewContainer("gcr.io/etcd-development/etcd:v3.5.5")
	if err := node1.RunDetach([]string{"--ip", node1Ip}, node1CmdArgs...); err != nil {
		t.Fatal(err)
	}

	node2Name := "node2"
	node2Ip := "10.188.2.61"

	id, err := etcdMemberAdd([]string{node1Ip}, node2Name, node2Ip)
	if err != nil {
		t.Fatal(err)
	}

	expect := fmt.Sprintf("node1=http://%s:%d,%s=http://%s:%d", node1Ip, etcdPeerPort, node2Name, node2Ip, etcdPeerPort)
	viper.SetConfigType("yaml")
	viper.SetConfigFile(etcdConfigFile)
	if err := viper.ReadInConfig(); err != nil {
		t.Fatal(err)
	}
	result := viper.GetString("initial-cluster")
	assert.ElementsMatch(t, strings.Split(expect, ","), strings.Split(result, ","))

	node2CmdArgs := []string{
		"etcd",
		"--name=" + node2Name,
		"--listen-client-urls=http://0.0.0.0:" + strconv.Itoa(etcdClientPort),
		"--advertise-client-urls=http://0.0.0.0:" + strconv.Itoa(etcdClientPort),
		"--listen-peer-urls=http://0.0.0.0:" + strconv.Itoa(etcdPeerPort),
		"--initial-advertise-peer-urls=http://" + node2Ip + ":" + strconv.Itoa(etcdPeerPort),
		"--initial-cluster-token=cube",
		"--initial-cluster-state=existing",
		"--initial-cluster=" + result,
	}

	node2 := ns.NewContainer("gcr.io/etcd-development/etcd:v3.5.5")
	if err := node2.RunDetach([]string{"--ip", node2Ip}, node2CmdArgs...); err != nil {
		t.Fatal(err)
	}

	// Wait for the learner to be in sync with leader
	//time.Sleep(1 * time.Second)

	if err := etcdMemberPromote([]string{node1Ip}, id); err != nil {
		t.Fatal(err)
	}
}

// func TestGetSelfEtcdMemberID(t *testing.T) {
// 	ns := cubeTesting.ContainerNS(t.Name())
// 	teardown := func() {
// 		ns.CleanupContainers()
// 	}

// 	t.Cleanup(teardown)
// 	teardown()

// 	name := "n1"
// 	ip := "10.188.2.11"
// 	_, err := ns.RunEtcdContainer(name, ip)
// 	if err != nil {
// 		t.Fatal(err)
// 	}

// 	if id, err := getSelfEtcdMemberID(ip, name); err != nil {
// 		t.Fatal(err)
// 	} else {
// 		assert.NotZero(t, id)
// 	}

// }

func TestEtcdListenClientUrls(t *testing.T) {
	tests := []struct {
		name     string
		settings map[string]string
		want     string
	}{
		{
			name: "NonHA",
			settings: map[string]string{
				"cubesys.management": "eth0",
				"net.if.addr.eth0":   "10.0.0.11",
			},
			want: "http://127.0.0.1:12379,http://10.0.0.11:12379",
		},
		{
			name: "HAWithVip",
			settings: map[string]string{
				"cubesys.management":  "eth0",
				"net.if.addr.eth0":    "10.0.0.11",
				"cubesys.ha":          "true",
				"cubesys.control.vip": "10.0.0.10",
			},
			want: "http://127.0.0.1:12379,http://10.0.0.11:12379,http://10.0.0.10:12379",
		},
		{
			name: "VipOnlyCountsInHA",
			settings: map[string]string{
				"cubesys.management":  "eth0",
				"net.if.addr.eth0":    "10.0.0.11",
				"cubesys.control.vip": "10.0.0.10",
			},
			want: "http://127.0.0.1:12379,http://10.0.0.11:12379",
		},
		{
			name: "VipSameAsMgmt",
			settings: map[string]string{
				"cubesys.management":  "eth0",
				"net.if.addr.eth0":    "10.0.0.11",
				"cubesys.ha":          "true",
				"cubesys.control.vip": "10.0.0.11",
			},
			want: "http://127.0.0.1:12379,http://10.0.0.11:12379",
		},
		{
			name: "NoMgmtIp",
			settings: map[string]string{
				"cubesys.management": "eth0",
			},
			want: "http://0.0.0.0:12379",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if err := cubeSettings.LoadMap(test.settings); err != nil {
				t.Fatal(err)
			}
			assert.Equal(t, test.want, etcdListenClientUrls(util.EtcdTLSPlain))
		})
	}
}

func TestRefreshEtcdConfig(t *testing.T) {
	setMode := useTestEtcdPKI(t)
	if err := cubeSettings.LoadMap(map[string]string{
		"cubesys.management": "eth0",
		"net.if.addr.eth0":   "10.0.0.11",
	}); err != nil {
		t.Fatal(err)
	}
	want := "http://127.0.0.1:12379,http://10.0.0.11:12379"

	readConf := func(t *testing.T, file string) *viper.Viper {
		v := viper.New()
		v.SetConfigFile(file)
		if err := v.ReadInConfig(); err != nil {
			t.Fatal(err)
		}
		return v
	}
	// a plain config as writeEtcdConfig has always written it on a joined node
	plainConf := strings.Join([]string{
		"advertise-client-urls: http://10.0.0.11:12379",
		"data-dir: /var/lib/etcd.cube",
		"initial-advertise-peer-urls: http://10.0.0.11:12380",
		"initial-cluster: cc1=http://10.0.0.11:12380,cc2=http://10.0.0.12:12380",
		"initial-cluster-state: existing",
		"initial-cluster-token: seed",
		"listen-client-urls: " + want,
		"listen-peer-urls: http://10.0.0.11:12380",
		"name: cc1",
		"",
	}, "\n")
	writeConf := func(t *testing.T, conf string) string {
		file := filepath.Join(t.TempDir(), "etcd.conf.yml")
		if err := os.WriteFile(file, []byte(conf), 0644); err != nil {
			t.Fatal(err)
		}
		return file
	}
	assertMembershipKept := func(t *testing.T, v *viper.Viper) {
		assert.Equal(t, "cc1", v.GetString("name"))
		assert.Equal(t, "/var/lib/etcd.cube", v.GetString("data-dir"))
		assert.Equal(t, "existing", v.GetString("initial-cluster-state"))
		assert.Equal(t, "seed", v.GetString("initial-cluster-token"))
		assert.Equal(t, "cc1=http://10.0.0.11:12380,cc2=http://10.0.0.12:12380", v.GetString("initial-cluster"))
	}

	t.Run("RewritesOnlyListenClientUrls", func(t *testing.T) {
		setMode(util.EtcdTLSPlain)
		file := writeConf(t, strings.Replace(plainConf, "listen-client-urls: "+want, "listen-client-urls: http://0.0.0.0:12379", 1))

		changed, err := refreshEtcdConfig(file)
		if err != nil {
			t.Fatal(err)
		}
		assert.True(t, changed)

		v := readConf(t, file)
		assert.Equal(t, want, v.GetString("listen-client-urls"))
		assert.Equal(t, "http://10.0.0.11:12380", v.GetString("listen-peer-urls"))
		assert.Equal(t, "http://10.0.0.11:12379", v.GetString("advertise-client-urls"))
		assert.Equal(t, "http://10.0.0.11:12380", v.GetString("initial-advertise-peer-urls"))
		assert.False(t, v.IsSet("client-transport-security"))
		assertMembershipKept(t, v)

		entries, err := os.ReadDir(filepath.Dir(file))
		if err != nil {
			t.Fatal(err)
		}
		assert.Len(t, entries, 1, "no temp file left behind")
	})

	t.Run("LeavesUpToDateFileAlone", func(t *testing.T) {
		setMode(util.EtcdTLSPlain)
		file := writeConf(t, plainConf)

		changed, err := refreshEtcdConfig(file)
		if err != nil {
			t.Fatal(err)
		}
		assert.False(t, changed)

		got, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		assert.Equal(t, plainConf, string(got))
	})

	t.Run("PlainToCompat", func(t *testing.T) {
		setMode(util.EtcdTLSCompat)
		file := writeConf(t, plainConf)

		changed, err := refreshEtcdConfig(file)
		if err != nil {
			t.Fatal(err)
		}
		assert.True(t, changed)

		v := readConf(t, file)
		assert.Equal(t, "http://127.0.0.1:12379,https://127.0.0.1:12379,http://10.0.0.11:12379,https://10.0.0.11:12379",
			v.GetString("listen-client-urls"))
		assert.Equal(t, "http://10.0.0.11:12380", v.GetString("listen-peer-urls"))
		assert.Equal(t, "http://10.0.0.11:12379", v.GetString("advertise-client-urls"))
		assert.Equal(t, util.EtcdMemberCertFile(), v.GetString("client-transport-security.cert-file"))
		assert.Equal(t, util.EtcdMemberCertFile(), v.GetString("peer-transport-security.cert-file"))
		assert.False(t, v.GetBool("client-transport-security.client-cert-auth"))
		assert.False(t, v.GetBool("peer-transport-security.client-cert-auth"))
		assertMembershipKept(t, v)

		changed, err = refreshEtcdConfig(file)
		assert.NoError(t, err)
		assert.False(t, changed, "second pass is a no-op")
	})

	t.Run("CompatToEnforce", func(t *testing.T) {
		setMode(util.EtcdTLSCompat)
		file := writeConf(t, plainConf)
		if _, err := refreshEtcdConfig(file); err != nil {
			t.Fatal(err)
		}

		setMode(util.EtcdTLSEnforce)
		changed, err := refreshEtcdConfig(file)
		if err != nil {
			t.Fatal(err)
		}
		assert.True(t, changed)

		v := readConf(t, file)
		assert.Equal(t, "https://127.0.0.1:12379,https://10.0.0.11:12379", v.GetString("listen-client-urls"))
		assert.Equal(t, "https://10.0.0.11:12380", v.GetString("listen-peer-urls"))
		assert.Equal(t, "https://10.0.0.11:12379", v.GetString("advertise-client-urls"))
		assert.True(t, v.GetBool("client-transport-security.client-cert-auth"))
		assert.True(t, v.GetBool("peer-transport-security.client-cert-auth"))
		assert.Equal(t, []string{util.EtcdMemberCN}, v.GetStringSlice("peer-transport-security.allowed-cn"))
		assertMembershipKept(t, v)
	})

	t.Run("EnforceBackToPlainDropsTLS", func(t *testing.T) {
		setMode(util.EtcdTLSEnforce)
		file := writeConf(t, plainConf)
		if _, err := refreshEtcdConfig(file); err != nil {
			t.Fatal(err)
		}

		setMode(util.EtcdTLSPlain)
		changed, err := refreshEtcdConfig(file)
		if err != nil {
			t.Fatal(err)
		}
		assert.True(t, changed)

		v := readConf(t, file)
		assert.False(t, v.IsSet("client-transport-security"))
		assert.False(t, v.IsSet("peer-transport-security"))
		assert.Equal(t, want, v.GetString("listen-client-urls"))
		assertMembershipKept(t, v)
	})

	t.Run("MissingFile", func(t *testing.T) {
		file := filepath.Join(t.TempDir(), "etcd.conf.yml")
		_, err := refreshEtcdConfig(file)
		assert.Error(t, err)
		_, err = os.Stat(file)
		assert.True(t, os.IsNotExist(err), "must not create a config")
	})
}
