package tests

import (
	"fmt"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"

	cubeTesting "cubectl/util/testing"
)

func TestClusterIpChanges(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		os.RemoveAll("/root/.ssh/")
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	control1Name := "control-1"
	control1Ip := "10.188.100.1"
	control1Role := "control"
	control1, err := ns.RunCubeContainer(control1Name, control1Ip, control1Role, nil)
	if err != nil {
		t.Fatal(err)
	}

	if _, outErr, err := control1.Exec(nil, "/usr/sbin/hex_config", "apply"); err != nil {
		t.Fatal(outErr, err)
	}

	compute1Name := "compute-1"
	compute1Ip := "10.188.100.11"
	compute1Role := "compute"
	compute1ExtraTunes := []string{
		"cubesys.controller.ip=" + control1Ip,
	}
	compute1, err := ns.RunCubeContainer(compute1Name, compute1Ip, compute1Role, compute1ExtraTunes)
	if err != nil {
		t.Fatal(err)
	}

	if _, outErr, err := compute1.Exec(nil, "/usr/sbin/hex_config", "apply"); err != nil {
		t.Fatal(outErr, err)
	}

	storage1Name := "storage-1"
	storage1Ip := "10.188.100.21"
	storage1Role := "storage"
	storage1ExtraTunes := []string{
		"cubesys.controller.ip=" + control1Ip,
	}
	storage1, err := ns.RunCubeContainer(storage1Name, storage1Ip, storage1Role, storage1ExtraTunes)
	if err != nil {
		t.Fatal(err)
	}

	if _, outErr, err := storage1.Exec(nil, "/usr/sbin/hex_config", "apply"); err != nil {
		t.Fatal(outErr, err)
	}

	// Generate ssh keys for public key auth
	// if _, outErr, err := cubeUtil.ExecCmd("ssh-keygen", "-f", "/root/.ssh/id_rsa", "-N", ""); err != nil {
	// 	t.Fatal(outErr, err)
	// }
	// if _, _, err := cubeUtil.ExecCmd("cp", "-f", "/root/.ssh/id_rsa.pub", "/root/.ssh/authorized_keys"); err != nil {
	// 	t.Fatal(err)
	// }
	// if _, outErr, err := control1.CopyTo(nil, "/root/.ssh/", "/root/"); err != nil {
	// 	t.Fatal(outErr, err)
	// }
	// if _, outErr, err := compute1.CopyTo(nil, "/root/.ssh/", "/root/"); err != nil {
	// 	t.Fatal(outErr, err)
	// }
	// if _, outErr, err := storage1.CopyTo(nil, "/root/.ssh/", "/root/"); err != nil {
	// 	t.Fatal(outErr, err)
	// }

	// Test
	if out, outErr, err := control1.Exec(nil, "cubectl", "node", "list"); err != nil {
		t.Fatal(outErr, err)
	} else {
		expectOut := fmt.Sprintf("%s,%s,%s\n%s,%s,%s\n%s,%s,%s\n",
			control1Name, control1Ip, control1Role,
			compute1Name, compute1Ip, compute1Role,
			storage1Name, storage1Ip, storage1Role)
		assert.Equal(t, expectOut, out)
	}

	// Remove all nodes
	// if _, outErr, err := control1.Exec(nil, "cubectl", "node", "remove", compute1Name, storage1Name); err != nil {
	// 	t.Fatal(outErr, err)
	// }
	// if _, outErr, err := control1.Exec(nil, "cubectl", "this-node", "leave"); err != nil {
	// 	t.Fatal(outErr, err)
	// }

	if _, outErr, err := control1.Exec(nil, "cubectl", "config", "reset", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := compute1.Exec(nil, "cubectl", "config", "reset", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := storage1.Exec(nil, "cubectl", "config", "reset", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	// Change IPs in cluster
	control1Ip = "10.188.100.101"
	compute1Ip = "10.188.100.111"
	storage1Ip = "10.188.100.121"
	if _, outErr, err := control1.Exec(nil, "/usr/sbin/hex_config", "apply", "ip", control1Ip); err != nil {
		t.Fatal(outErr, err)
	}

	if _, outErr, err := compute1.Exec(nil, "sh", "-c", "echo cubesys.controller.ip="+control1Ip+" >> /etc/settings.txt"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := compute1.Exec(nil, "/usr/sbin/hex_config", "apply", "ip", compute1Ip); err != nil {
		t.Fatal(outErr, err)
	}

	if _, outErr, err := storage1.Exec(nil, "sh", "-c", "echo cubesys.controller.ip="+control1Ip+" >> /etc/settings.txt"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := storage1.Exec(nil, "/usr/sbin/hex_config", "apply", "ip", storage1Ip); err != nil {
		t.Fatal(outErr, err)
	}

	// Test
	if out, outErr, err := control1.Exec(nil, "cubectl", "node", "list"); err != nil {
		t.Fatal(outErr, err)
	} else {
		expectOut := fmt.Sprintf("%s,%s,%s\n%s,%s,%s\n%s,%s,%s\n",
			control1Name, control1Ip, control1Role,
			compute1Name, compute1Ip, compute1Role,
			storage1Name, storage1Ip, storage1Role)
		assert.Equal(t, expectOut, out)
	}
}
