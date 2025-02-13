package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"strconv"
	"testing"
	"time"

	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"

	cubeUtil "cubectl/util"
	cubeSettings "cubectl/util/settings"
	cubeTesting "cubectl/util/testing"
)

func TestRunTuningPush(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	etcdServer, err := RunEtcdContainer(ns)
	if err != nil {
		t.Fatal(err)
	}

	t.Run("NodeWithSingleStorage", func(t *testing.T) {
		//memberID := "XXXX"
		ip := "1.1.1.1"
		hostname := "client-1"
		role := "storage"

		expectNodeInfo := cubeUtil.Node{
			Hostname: hostname,
			Role:     role,
			IP: cubeUtil.NodeIP{
				Management: ip,
				Provider:   ip,
				Overlay:    ip,
				Storage:    ip,
			},
		}

		if err := cubeSettings.LoadMap(
			map[string]string{
				"cubesys.role":          role,
				"cubesys.management":    "eth0",
				"cubesys.provider":      "eth0",
				"cubesys.overlay":       "eth0",
				"cubesys.storage":       "eth0",
				"net.if.addr.eth0":      ip,
				"net.hostname":          hostname,
				"cubesys.controller.ip": etcdServer.IP,
			},
		); err != nil {
			t.Fatal(err)
		}
		//t.Log(cubeSettings.V())

		// if err := ioutil.WriteFile(memberIDFile, []byte(memberID), 0644); err != nil {
		// 	t.Fatal(err)
		// }

		if err := runTuningPush(nil, []string{}); err != nil {
			t.Fatal(err)
		}

		if out, _, err := cubeUtil.ExecCmd(
			"etcdctl", "get",
			"--print-value-only",
			"cluster.node."+hostname,
			"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort),
		); err != nil {
			t.Fatal(err)
		} else {
			var nodeInfo cubeUtil.Node
			if err := json.Unmarshal([]byte(out), &nodeInfo); err != nil {
				t.Fatal(err)
			}
			assert.Equal(t, expectNodeInfo, nodeInfo)
		}
	})

	t.Run("NodeWithStorageCluster", func(t *testing.T) {
		//memberID := "YYYY"
		ip := "2.2.2.2"
		hostname := "client-2"
		role := "storage"

		expectNodeInfo := cubeUtil.Node{
			Hostname: hostname,
			Role:     role,
			IP: cubeUtil.NodeIP{
				Management:     ip,
				Provider:       ip,
				Overlay:        ip,
				Storage:        ip,
				StorageCluster: ip,
			},
		}

		if err := cubeSettings.LoadMap(
			map[string]string{
				"cubesys.role":          role,
				"cubesys.management":    "eth0",
				"cubesys.provider":      "eth0",
				"cubesys.overlay":       "eth0",
				"cubesys.storage":       "eth0,eth1",
				"net.if.addr.eth0":      ip,
				"net.if.addr.eth1":      ip,
				"net.hostname":          hostname,
				"cubesys.controller.ip": etcdServer.IP,
			},
		); err != nil {
			t.Fatal(err)
		}
		//t.Log(cubeSettings.V())

		// if err := ioutil.WriteFile(memberIDFile, []byte(memberID), 0644); err != nil {
		// 	t.Fatal(err)
		// }

		if err := runTuningPush(nil, []string{}); err != nil {
			t.Fatal(err)
		}

		if out, _, err := cubeUtil.ExecCmd(
			"etcdctl", "get",
			"--print-value-only",
			"cluster.node."+hostname,
			"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort),
		); err != nil {
			t.Fatal(err)
		} else {
			var nodeInfo cubeUtil.Node
			if err := json.Unmarshal([]byte(out), &nodeInfo); err != nil {
				t.Fatal(err)
			}
			assert.Equal(t, expectNodeInfo, nodeInfo)
		}
	})
	/*
		hostname := gjson.Get(out, "hostname")
		ip := gjson.Get(strings.TrimRight(out, "\n"), "ip.management")
		t.Log(hostname)
		t.Log(ip)
	*/
}

func TestRunTuningPullRemove(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		os.Remove(clusterTuningFile)
		os.RemoveAll(stagingDir)
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	etcdServer, err := RunEtcdContainer(ns)
	if err != nil {
		t.Fatal(err)
	}

	//memberID := "ZZZZ"
	hostname := "compute-1"

	if err := cubeSettings.LoadMap(
		map[string]string{
			"cubesys.controller.ip": etcdServer.IP,
		},
	); err != nil {
		t.Fatal(err)
	}

	// if err := ioutil.WriteFile(memberIDFile, []byte(memberID), 0644); err != nil {
	// 	t.Fatal(err)
	// }

	if _, _, err := cubeUtil.ExecCmd(
		"etcdctl", "put",
		"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort),
		"cluster.node."+hostname, `{}`,
	); err != nil {
		t.Fatal(err)
	}

	timePolicyPath := "time/time1_0"
	timePolicy := `
name: time
version: 1.0
timezone: Asia/Taipei
`

	if _, _, err := cubeUtil.ExecCmd(
		"etcdctl", "put",
		"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort),
		"cluster._all_."+timePolicyPath, timePolicy,
	); err != nil {
		t.Fatal(err)
	}

	t.Run("Pull", func(t *testing.T) {
		if err := runTuningPull(nil, []string{}); err != nil {
			t.Fatal(err)
		}

		if nodes, err := cubeUtil.LoadClusterSettings(); err != nil {
			t.Fatal(err)
		} else {

			if node, ok := (*nodes)[hostname]; !ok {
				t.Fatal(err)
			} else {
				assert.Equal(t, cubeUtil.Node{}, node)
			}
		}

		viper.SetConfigType("yaml")
		viper.SetConfigFile(stagingPolicyDir + "/" + timePolicyPath + ".yaml")
		if err := viper.ReadInConfig(); err != nil {
			t.Fatal(err)
		} else {
			assert.Equal(t, "time", viper.GetString("name"))
			assert.Equal(t, "Asia/Taipei", viper.GetString("timezone"))
		}
	})

	t.Run("Remove", func(t *testing.T) {
		if err := runTuningRemove(nil, []string{}); err != nil {
			t.Fatal(err)
		}

		if out, _, err := cubeUtil.ExecCmd(
			"etcdctl", "get",
			"--print-value-only",
			"--prefix",
			"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort),
			"cluster.node."+hostname,
		); err != nil {
			t.Fatal(err)
		} else {
			assert.Empty(t, out)
		}
	})

	t.Run("Revision", func(t *testing.T) {
		oldRev, err := etcdGetLatestRevision()
		if err != nil {
			t.Fatal(err)
		}

		if _, _, err := cubeUtil.ExecCmd("etcdctl", "put",
			"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort), "foo", "bar",
		); err != nil {
			t.Fatal(err)
		}

		newRev, err := etcdGetLatestRevision()
		if err != nil {
			t.Fatal(err)
		}

		assert.Equal(t, oldRev+1, newRev)
	})
}

func TestRunTuningWatch(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		os.Remove(settingsFile)
		os.Remove(clusterTuningFile)
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	etcdServer, err := RunEtcdContainer(ns)
	if err != nil {
		t.Fatal(err)
	}

	role := "compute"
	settingsStr := "cubesys.role = " + role + "\n" +
		"cubesys.controller.ip = " + etcdServer.IP + "\n"

	if err := cubeTesting.GenerateSettingsRaw(settingsFile, settingsStr); err != nil {
		t.Fatal(err)
	} else {
		if err := cubeSettings.Load(); err != nil {
			t.Fatal(err)
		}
	}

	//go func() {
	//	_ = runTuningWatch(nil, []string{})
	//}()

	// FIXME: wait until watch process is started
	//time.Sleep(1 * time.Second)

	cmd := exec.Command("cubectl", "tuning", "watch")
	var errByte bytes.Buffer
	cmd.Stderr = &errByte

	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}

	nodeInfo := cubeUtil.Node{
		Hostname: "node1",
		IP: cubeUtil.NodeIP{
			Management: "1.1.1.1",
		},
		Role: "storage",
	}

	jsonBytes, _ := json.Marshal(nodeInfo)

	if _, _, err := cubeUtil.ExecCmd(
		"etcdctl", "put",
		"--endpoints="+etcdServer.IP+":"+strconv.Itoa(etcdClientPort),
		"cluster.node.node1", string(jsonBytes),
	); err != nil {
		t.Fatal(err)
	}

	// Waiting on output
	time.Sleep(2 * time.Second)

	if err := cmd.Process.Kill(); err != nil {
		t.Fatal(err)
	}

	outErr := errByte.String()
	t.Log(outErr)

	assert.Contains(t, outErr, "Cluster was changed, applying tuning")
	assert.Contains(t, outErr, `"msg":"Triggered cluster_map_update","action":"add","hostname":"node1","ip":"1.1.1.1","role":"storage"`)

	/* 	expect := `{"xxxx":{"hostname":"","role":"","ip":{"management":""}}}`

	   	timeout := 10
	   	for i := 0; ; {
	   		if dataByte, err := ioutil.ReadFile(clusterTuningFile); err != nil {
	   			if i >= timeout {
	   				t.Fatal(err)
	   			}

	   			time.Sleep(1 * time.Second)
	   			i++
	   			continue
	   		} else {
	   			assert.Equal(t, expect, string(dataByte))
	   			break
	   		}
	   	} */

}
