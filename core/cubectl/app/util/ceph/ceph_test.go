package ceph

import (
	"encoding/base64"
	"encoding/binary"
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

func cephKey(keyType uint16, secret []byte) string {
	raw := make([]byte, 12+len(secret))
	binary.LittleEndian.PutUint16(raw[0:2], keyType)
	copy(raw[2:10], []byte{1, 2, 3, 4, 5, 6, 7, 8})
	binary.LittleEndian.PutUint16(raw[10:12], uint16(len(secret)))
	copy(raw[12:], secret)
	return base64.StdEncoding.EncodeToString(raw)
}

// A key from `ceph-authtool --gen-print-key --key-type aes256k` (Ceph 19.2.7),
// and its AES-128 form, which the kernel accepted through cephcsi v3.13.1's
// mount.ceph where the original was refused.
func TestAes128MountKeyFixture(t *testing.T) {
	const aes256k = "AgBZt/ZqsCPNJCAARI9SkLjQSeiLYaHETYocUalC5oMj1tsn2xPhF8QaY3k="
	const want = "AQBZt/ZqsCPNJBAARI9SkLjQSeiLYaHETYocUQ=="

	got, err := aes128MountKey(aes256k)
	if err != nil {
		t.Fatalf("aes128MountKey: %v", err)
	}
	if got != want {
		t.Errorf("got %s, want %s", got, want)
	}
}

// cephcsi v3.13.1's mount.ceph only reads a 40-character AES-128 key; an
// aes256k admin key (60 characters) must reach the cephfs chart re-encoded.
func TestAes128MountKey(t *testing.T) {
	secret := make([]byte, 32)
	for i := range secret {
		secret[i] = byte(0x40 + i)
	}

	got, err := aes128MountKey(cephKey(2, secret))
	if err != nil {
		t.Fatalf("aes256k: %v", err)
	}
	if want := cephKey(1, secret[:16]); got != want {
		t.Errorf("aes256k: got %s, want %s", got, want)
	}
	if len(got) != 40 {
		t.Errorf("aes256k: got a %d-character key, want 40", len(got))
	}

	aes := cephKey(1, secret[:16])
	if got, err := aes128MountKey(aes); err != nil || got != aes {
		t.Errorf("aes: got %q, %v; want it unchanged", got, err)
	}

	for name, key := range map[string]string{
		"not base64":      "not a key!",
		"short header":    base64.StdEncoding.EncodeToString([]byte{2, 0, 1}),
		"length mismatch": cephKey(2, secret)[:40],
		"short secret":    cephKey(2, secret[:8]),
	} {
		if got, err := aes128MountKey(key); err == nil {
			t.Errorf("%s: got %q, want an error", name, got)
		}
	}
}
