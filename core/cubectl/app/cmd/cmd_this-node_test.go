package cmd

import (
	"strconv"
	"testing"

	cubeTesting "cubectl/util/testing"

	"github.com/stretchr/testify/assert"
)

func TestThisnodeAddJoin(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	testClean := func() {
		ns.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	control1Name := "control-1"
	control2Name := "control-2"
	control3Name := "control-3"
	control1Ip := "10.188.8.11"
	control2Ip := "10.188.8.21"
	control3Ip := "10.188.8.31"

	settingsHA := []string{
		"cubesys.ha=true",
		"cubesys.control.hosts=" + control1Name + "," + control2Name + "," + control3Name,
		"cubesys.control.addrs=" + control1Ip + "," + control2Ip + "," + control3Ip,
	}

	control1, err := ns.RunCubeContainer(control1Name, control1Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control1.Exec(nil, "cubectl", "this-node", "new"); err != nil {
		t.Fatal(outErr, err)
	}

	control2, err := ns.RunCubeContainer(control2Name, control2Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control2.Exec(nil, "cubectl", "this-node", "join"); err != nil {
		t.Fatal(outErr, err)
	}

	control3, err := ns.RunCubeContainer(control3Name, control3Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control3.Exec(nil, "cubectl", "this-node", "join"); err != nil {
		t.Fatal(outErr, err)
	}

	//Test
	if out, outErr, err := control1.Exec(nil, "etcdctl", "--endpoints=127.0.0.1:"+strconv.Itoa(etcdClientPort), "member", "list"); err != nil {
		t.Fatal(outErr, err)
	} else {
		assert.Contains(t, out, control1Name)
		assert.Contains(t, out, control2Name)
		assert.Contains(t, out, control3Name)
	}
}
