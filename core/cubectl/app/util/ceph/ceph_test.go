package ceph

import (
	"os"
	"testing"
)

// Mon endpoints live on the storage network, never on the management network,
// so the parser must not filter them against a node's mgmt IP.
func TestParseMonitorHostsOnStorageNetwork(t *testing.T) {
	conf := `[global]
mon initial members = sky141,sky143,sky142,
mon host = [v2:172.18.95.141:3300/0,v1:172.18.95.141:6789/0],[v2:172.18.95.143:3300/0,v1:172.18.95.143:6789/0],[v2:172.18.95.142:3300/0,v1:172.18.95.142:6789/0],
mon max pg per osd = 4096
`
	f, err := os.CreateTemp(t.TempDir(), "ceph.conf")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(conf); err != nil {
		t.Fatal(err)
	}
	if _, err := f.Seek(0, 0); err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	hosts, err := parseMonitorHosts(f)
	if err != nil {
		t.Fatalf("parseMonitorHosts: %v", err)
	}

	want := []string{"172.18.95.141:6789", "172.18.95.143:6789", "172.18.95.142:6789"}
	if len(hosts) != len(want) {
		t.Fatalf("got %d hosts %v, want %d %v", len(hosts), hosts, len(want), want)
	}
	for i := range want {
		if hosts[i] != want[i] {
			t.Errorf("host[%d] = %q, want %q", i, hosts[i], want[i])
		}
	}
}
