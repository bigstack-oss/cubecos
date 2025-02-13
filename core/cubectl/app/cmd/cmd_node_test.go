package cmd

import (
	"fmt"
	"io/ioutil"
	"os"
	"testing"
	"time"

	"github.com/kami-zh/go-capturer"
	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
	cubeTesting "cubectl/util/testing"
)

func TestRunNodeList(t *testing.T) {
	testClean := func() {
		os.Remove(clusterTuningFile)
	}
	testClean()
	t.Cleanup(testClean)

	// make CONTROL-1 in uppercase to test case insensitive hostname
	jsonByte := []byte(`
{
	"compute-1": {
		"hostname": "compute-1",
		"ip": {
		"management": "5.5.5.11"
		},
		"role": "compute"
	},
	"storage-1": {
		"hostname": "storage-1",
		"ip": {
		"management": "5.5.5.21"
		},
		"role": "storage"
	},
	"control-3": {
		"hostname": "control-3",
		"ip": {
		"management": "5.5.5.3"
		},
		"role": "control"
	},
	"CONTROL-1": {
		"hostname": "control-1",
		"ip": {
		"management": "5.5.5.1"
		},
		"role": "control-converged"
	},
	"control-2": {
		"hostname": "control-2",
		"ip": {
		"management": "5.5.5.2"
		},
		"role": "control-network"
	}
}`)

	if err := ioutil.WriteFile(clusterTuningFile, jsonByte, 0644); err != nil {
		t.Fatal(err)
	}

	t.Run("NoOptions", func(t *testing.T) {
		out := capturer.CaptureStdout(func() {
			_ = runNodeList(nil, []string{})
		})

		expectOut := `control-1,5.5.5.1,control-converged
control-2,5.5.5.2,control-network
control-3,5.5.5.3,control
compute-1,5.5.5.11,compute
storage-1,5.5.5.21,storage
`

		assert.Equal(t, expectOut, out)
	})

	t.Run("FilterRole", func(t *testing.T) {
		out := capturer.CaptureStdout(func() {
			listOpts.role = "control"
			_ = runNodeList(nil, []string{})
		})

		expectOut := `control-1,5.5.5.1,control-converged
control-2,5.5.5.2,control-network
control-3,5.5.5.3,control
`

		assert.Equal(t, expectOut, out)
	})

	t.Run("FilterRoleJson", func(t *testing.T) {
		out := capturer.CaptureStdout(func() {
			listOpts.role = "control"
			listOpts.json = true
			_ = runNodeList(nil, []string{})
		})

		expectOut := `
[
	{"hostname":"control-1","ip":{"management":"5.5.5.1"},"role":"control-converged"},
	{"hostname":"control-2","ip":{"management":"5.5.5.2"},"role":"control-network"},
	{"hostname":"control-3","ip":{"management":"5.5.5.3"},"role":"control"}
]`

		assert.JSONEq(t, expectOut, out)
	})

	t.Run("HAControlNodes", func(t *testing.T) {

		// 		settingsText := `
		// cubesys.ha = true
		// cubesys.control.hosts = control-3,control-2,control-1
		// `

		// 		if err := cubeTesting.GenerateSettingsRaw(settingsFile, settingsText); err != nil {
		// 			t.Fatal(err)
		// 		}

		if err := cubeSettings.LoadMap(
			map[string]string{
				"cubesys.ha":            "true",
				"cubesys.control.hosts": "control-3,control-2,CONTROL-1",
			},
		); err != nil {
			t.Fatal(err)
		}

		out := capturer.CaptureStdout(func() {
			listOpts.role = "control"
			listOpts.json = true
			_ = runNodeList(nil, []string{})
		})

		expectOut := `
[
	{"hostname":"control-3","ip":{"management":"5.5.5.3"},"role":"control"},
	{"hostname":"control-2","ip":{"management":"5.5.5.2"},"role":"control-network"},
	{"hostname":"control-1","ip":{"management":"5.5.5.1"},"role":"control-converged"}
]`

		assert.JSONEq(t, expectOut, out)
	})
}

func TestRunNodeExec(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		os.RemoveAll("/root/.ssh/")
		os.Remove(util.ClusterSettingsFile)
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	// Generate ssh keys for public key auth
	if _, _, err := util.ExecCmd("ssh-keygen", "-f", "/root/.ssh/id_rsa", "-N", ""); err != nil {
		t.Fatal(err)
	}
	if _, _, err := util.ExecCmd("cp", "-f", "/root/.ssh/id_rsa.pub", "/root/.ssh/authorized_keys"); err != nil {
		t.Fatal(err)
	}

	n1Name := "n1"
	n1Ip := "10.188.3.11"
	if n1, err := ns.RunCubeContainer(n1Name, n1Ip, "compute", nil); err != nil {
		t.Fatal(err)
	} else {
		n1.CopyTo(nil, "/root/.ssh/", "/root/")

		time.Sleep(1 * time.Second)
	}

	// Wait to prevent podman IP allocation error
	//time.Sleep(5 * time.Second)

	n2Name := "n2"
	n2Ip := "10.188.3.21"
	if n2, err := ns.RunCubeContainer(n2Name, n2Ip, "compute", nil); err != nil {
		t.Fatal(err)
	} else {
		n2.CopyTo(nil, "/root/.ssh/", "/root/")

		time.Sleep(1 * time.Second)
	}

	settingsClusterJson := `
{
	"` + n1Name + `":{"hostname":"` + n1Name + `","role":"control","ip":{"management":"` + n1Ip + `"}},
	"` + n2Name + `":{"hostname":"` + n2Name + `","role":"compute","ip":{"management":"` + n2Ip + `"}}
}`
	if err := ioutil.WriteFile(util.ClusterSettingsFile, []byte(settingsClusterJson), 0644); err != nil {
		t.Fatal(err)
	}

	t.Run("PasswordAuth", func(t *testing.T) {
		t.Parallel()
		out := capturer.CaptureOutput(func() {
			execOpts.hosts = []string{n1Ip}
			execOpts.userPasswd = "root:admin"
			_ = runNodeExec(nil, []string{"pwd"})
		})

		assert.Equal(t, "/root\n", out)
	})

	t.Run("PublicKeyAuth", func(t *testing.T) {
		t.Parallel()
		_, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--hosts="+n1Ip, "true")
		if err != nil {
			t.Fatal(outErr, err)
		}
	})

	t.Run("CommandWithEnv", func(t *testing.T) {
		t.Parallel()
		out, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--hosts="+n1Ip, "TESTEVN=1", "env")
		if err != nil {
			t.Fatal(outErr, err)
		}

		assert.Contains(t, out, "TESTEVN=1")
	})

	t.Run("MultipleHostsPassword", func(t *testing.T) {
		t.Parallel()
		out, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--hosts="+n1Ip, "--hosts="+n2Ip, "--user=root:admin", "pwd")
		if err != nil {
			t.Fatal(outErr, err)
		}

		assert.Equal(t, "/root\n/root\n", out)
	})

	t.Run("MultipleHostsParallell", func(t *testing.T) {
		t.Parallel()
		out, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--hosts="+n1Ip, "--hosts="+n2Ip, "--parallel", "cat", "/etc/hostname")
		if err != nil {
			t.Fatal(outErr, err)
		}

		assert.Contains(t, out, n1Name)
		assert.Contains(t, out, n2Name)
	})

	t.Run("ParallelTimeout", func(t *testing.T) {
		t.Parallel()
		_, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--hosts="+n1Ip, "--parallel", "--timeout=1", "sleep 2")

		//t.Log(outErr)
		assert.Error(t, err)
		assert.Contains(t, outErr, "Timed out")
	})

	t.Run("WrongPassword", func(t *testing.T) {
		t.Parallel()
		_, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--hosts="+n1Ip, "--user=root:xxxx", "pwd")

		//t.Log(outErr)
		assert.Error(t, err)
		assert.Contains(t, outErr, "ssh: unable to authenticate")
	})

	t.Run("AllRoles", func(t *testing.T) {
		t.Parallel()

		out, outErr, err := util.ExecCmd("cubectl", "node", "exec", "hostname")
		if err != nil {
			t.Fatal(outErr, err)
		}

		assert.Equal(t, fmt.Sprintf("%s\n%s\n", n1Name, n2Name), out)
	})

	t.Run("SpecificRole", func(t *testing.T) {
		t.Parallel()

		out, outErr, err := util.ExecCmd("cubectl", "node", "exec", "--role=control", "hostname")
		if err != nil {
			t.Fatal(outErr, err)
		}

		assert.Equal(t, fmt.Sprintf("%s\n", n1Name), out)
	})

}

func TestRunNodeAddRemove(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		os.Remove(util.ClusterSettingsFile)
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	control1Name := "control-1"
	control1Ip := "10.188.3.32"
	control1Role := "control"
	control1, err := ns.RunCubeContainer(control1Name, control1Ip, control1Role, nil)
	if err != nil {
		t.Fatal(err)
	}

	compute1Name := "compute-1"
	compute1Ip := "10.188.3.42"
	compute1Role := "compute"
	compute1, err := ns.RunCubeContainer(compute1Name, compute1Ip, compute1Role, []string{
		"cubesys.controller.ip=" + control1Ip,
	})
	if err != nil {
		t.Fatal(err)
	}

	storage1Name := "storage-1"
	storage1Ip := "10.188.3.52"
	storage1Role := "storage"
	storage1, err := ns.RunCubeContainer(storage1Name, storage1Ip, storage1Role, []string{
		"cubesys.controller.ip=" + control1Ip,
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, outErr, err := control1.Exec(nil, "cubectl", "this-node", "new"); err != nil {
		t.Fatal(outErr, err)
	}

	if _, outErr, err := control1.Exec(nil, "cubectl", "node", "add", compute1Ip, storage1Ip); err != nil {
		t.Fatal(outErr, err)
	}

	if out, outErr, err := control1.Exec(nil, "cubectl", "node", "list"); err != nil {
		t.Fatal(outErr, err)
	} else {
		expectOut := fmt.Sprintf("%s,%s,%s\n%s,%s,%s\n%s,%s,%s\n",
			control1Name, control1Ip, control1Role,
			compute1Name, compute1Ip, compute1Role,
			storage1Name, storage1Ip, storage1Role,
		)
		assert.Equal(t, expectOut, out)
	}

	// Remove from cluster
	if _, outErr, err := control1.Exec(nil, "cubectl", "node", "remove", compute1Name, storage1Name); err != nil {
		t.Fatal(outErr, err)
	}

	if _, outErr, err := compute1.Exec(nil, "cubectl", "this-node", "reset"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := storage1.Exec(nil, "cubectl", "this-node", "reset"); err != nil {
		t.Fatal(outErr, err)
	}

	// Test
	if out, outErr, err := control1.Exec(nil, "cubectl", "node", "list"); err != nil {
		t.Fatal(outErr, err)
	} else {
		expectOut := fmt.Sprintf("%s,%s,%s\n",
			control1Name, control1Ip, control1Role,
		)
		assert.Equal(t, expectOut, out)
	}

	// Re-add to cluster
	if _, outErr, err := control1.Exec(nil, "cubectl", "node", "add", compute1Ip, storage1Ip); err != nil {
		t.Fatal(outErr, err)
	}

	if out, outErr, err := control1.Exec(nil, "cubectl", "node", "list"); err != nil {
		t.Fatal(outErr, err)
	} else {
		expectOut := fmt.Sprintf("%s,%s,%s\n%s,%s,%s\n%s,%s,%s\n",
			control1Name, control1Ip, control1Role,
			compute1Name, compute1Ip, compute1Role,
			storage1Name, storage1Ip, storage1Role,
		)
		assert.Equal(t, expectOut, out)
	}
}

func TestRunNodeRsync(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		ns.CleanupContainers()
		os.RemoveAll("/root/.ssh/")
		os.RemoveAll("/tmp/" + t.Name())
	}
	testClean()
	t.Cleanup(testClean)

	if _, _, err := util.ExecShf(`ssh-keygen -f /root/.ssh/id_rsa -N "" && cp -f /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys`); err != nil {
		t.Fatal(err)
	}

	n1 := ns.NewContainer("docker.io/hermsi/alpine-sshd")
	if err := n1.RunDetach(
		[]string{
			"--env", "ROOT_KEYPAIR_LOGIN_ENABLED=true",
			"--volume", "/root/.ssh/authorized_keys:/root/.ssh/authorized_keys",
		},
	); err != nil {
		t.Fatal(err)
	}

	n2 := ns.NewContainer("docker.io/hermsi/alpine-sshd")
	if err := n2.RunDetach(
		[]string{
			"--env", "ROOT_KEYPAIR_LOGIN_ENABLED=true",
			"--volume", "/root/.ssh/authorized_keys:/root/.ssh/authorized_keys",
		},
	); err != nil {
		t.Fatal(err)
	}

	// Generate files on remote
	if _, outErr, err := n1.Exec(nil, "mkdir", "-p", "/tmp/"+t.Name()); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := n1.Exec(nil, "sh", "-c", "cd /tmp/"+t.Name()+" && touch 1 2"); err != nil {
		t.Fatal(outErr, err)
	}

	// rsysnc files from remote
	if _, _, err := util.ExecCmd("cubectl", "node", "rsync",
		n1.IP+":/tmp/"+t.Name()+"/1",
	); err != nil {
		t.Fatal(err)
	} else {
		assert.FileExists(t, "/tmp/"+t.Name()+"/1")
	}

	// rsysnc dir from remote
	if _, _, err := util.ExecCmd("cubectl", "node", "rsync",
		n1.IP+":/tmp/"+t.Name(),
	); err != nil {
		t.Fatal(err)
	} else {
		assert.FileExists(t, "/tmp/"+t.Name()+"/1")
		assert.FileExists(t, "/tmp/"+t.Name()+"/2")
	}

	// rsysnc dir to remote
	if _, _, err := util.ExecCmd("cubectl", "node", "rsync",
		"/tmp/"+t.Name(),
		"--hosts", n1.IP+","+n2.IP,
	); err != nil {
		t.Fatal(err)
	} else {
		if out, outErr, err := n1.Exec(nil, "ls", "/tmp/"+t.Name()); err != nil {
			t.Fatal(outErr, err)
		} else {
			assert.Equal(t, "1\n2\n", out)
		}

		if out, outErr, err := n2.Exec(nil, "ls", "/tmp/"+t.Name()); err != nil {
			t.Fatal(outErr, err)
		} else {
			assert.Equal(t, "1\n2\n", out)
		}
	}

	// rsysnc to remote with deletion
	os.Remove("/tmp/" + t.Name() + "/1")
	if _, _, err := util.ExecCmd("cubectl", "node", "rsync",
		"/tmp/"+t.Name(),
		"--hosts", n1.IP+","+n2.IP,
		"--delete",
	); err != nil {
		t.Fatal(err)
	} else {
		if out, outErr, err := n1.Exec(nil, "ls", "/tmp/"+t.Name()); err != nil {
			t.Fatal(outErr, err)
		} else {
			assert.Equal(t, "2\n", out)
		}

		if out, outErr, err := n2.Exec(nil, "ls", "/tmp/"+t.Name()); err != nil {
			t.Fatal(outErr, err)
		} else {
			assert.Equal(t, "2\n", out)
		}
	}
}
