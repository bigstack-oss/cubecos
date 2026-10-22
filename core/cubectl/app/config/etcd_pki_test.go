package config

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

var etcdPKITestSettings = map[string]string{
	"cubesys.role":          "control",
	"cubesys.ha":            "true",
	"cubesys.controller":    "sky",
	"cubesys.control.vip":   "10.32.10.140",
	"cubesys.control.addrs": "10.32.10.141,10.32.10.142,10.32.10.143",
	"cubesys.control.hosts": "sky141,sky142,sky143",
}

func readTestCert(t *testing.T, path string) *x509.Certificate {
	t.Helper()
	b, err := os.ReadFile(path)
	require.NoError(t, err)
	block, _ := pem.Decode(b)
	require.NotNil(t, block, path)
	cert, err := x509.ParseCertificate(block.Bytes)
	require.NoError(t, err)
	return cert
}

func certSANs(cert *x509.Certificate) []string {
	var out []string
	for _, n := range cert.DNSNames {
		out = append(out, "DNS:"+n)
	}
	for _, ip := range cert.IPAddresses {
		out = append(out, "IP:"+ip.String())
	}
	sort.Strings(out)
	return out
}

func TestGenEtcdPKI(t *testing.T) {
	require.NoError(t, cubeSettings.LoadMap(etcdPKITestSettings))

	dir := filepath.Join(t.TempDir(), "pki")
	require.NoError(t, genEtcdPKIInto(dir))

	for name, mode := range map[string]os.FileMode{
		"ca.crt": 0644, "ca.key": 0600,
		"member.crt": 0644, "member.key": 0600,
		"client.crt": 0644, "client.key": 0600,
		"terraform-backend.hcl": 0644,
	} {
		fi, err := os.Stat(filepath.Join(dir, name))
		if assert.NoError(t, err, name) {
			assert.Equal(t, mode, fi.Mode().Perm(), name)
		}
	}
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	assert.Len(t, entries, 7)

	ca := readTestCert(t, filepath.Join(dir, "ca.crt"))
	member := readTestCert(t, filepath.Join(dir, "member.crt"))
	client := readTestCert(t, filepath.Join(dir, "client.crt"))

	t.Run("CA", func(t *testing.T) {
		assert.Equal(t, util.EtcdCACN, ca.Subject.CommonName)
		assert.True(t, ca.IsCA)
		assert.True(t, ca.MaxPathLenZero)
	})

	pool := x509.NewCertPool()
	pool.AddCert(ca)

	t.Run("Member", func(t *testing.T) {
		assert.Equal(t, util.EtcdMemberCN, member.Subject.CommonName)
		assert.False(t, member.IsCA)
		assert.ElementsMatch(t, []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}, member.ExtKeyUsage)

		want := strings.Split(strings.TrimPrefix(buildCertSANs(), "subjectAltName="), ",")
		sort.Strings(want)
		assert.Equal(t, want, certSANs(member))

		for _, usage := range []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth} {
			_, err := member.Verify(x509.VerifyOptions{Roots: pool, KeyUsages: []x509.ExtKeyUsage{usage}})
			assert.NoError(t, err, usage)
		}
		_, err := member.Verify(x509.VerifyOptions{Roots: pool, DNSName: "10.32.10.142"})
		assert.NoError(t, err, "serves a control node's address")

		// the check gencerts runs before it replaces a certificate passes on this one
		assert.NoError(t, verifyCertCoversControlGroup(filepath.Join(dir, "member.crt")))
	})

	t.Run("Client", func(t *testing.T) {
		assert.Equal(t, util.EtcdClientCN, client.Subject.CommonName)
		assert.Equal(t, []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}, client.ExtKeyUsage)
		assert.Empty(t, certSANs(client))

		_, err := client.Verify(x509.VerifyOptions{Roots: pool, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}})
		assert.NoError(t, err)
		_, err = client.Verify(x509.VerifyOptions{Roots: pool, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}})
		assert.Error(t, err, "cannot serve")
	})

	t.Run("Lifetime", func(t *testing.T) {
		for _, c := range []*x509.Certificate{ca, member, client} {
			days := c.NotAfter.Sub(c.NotBefore).Hours() / 24
			assert.InDelta(t, etcdCertDays, days, 1, c.Subject.CommonName)
			assert.True(t, c.NotBefore.Before(time.Now()), c.Subject.CommonName)
		}
	})

	t.Run("KeysMatch", func(t *testing.T) {
		for _, name := range []string{"ca", "member", "client"} {
			_, err := tls.LoadX509KeyPair(filepath.Join(dir, name+".crt"), filepath.Join(dir, name+".key"))
			assert.NoError(t, err, name)
		}
	})

	t.Run("TerraformBackend", func(t *testing.T) {
		b, err := os.ReadFile(filepath.Join(dir, "terraform-backend.hcl"))
		require.NoError(t, err)
		hcl := string(b)
		assert.Contains(t, hcl, `endpoints   = ["https://127.0.0.1:12379"]`)
		assert.Contains(t, hcl, `cacert_path = "/etc/etcd-pki/ca.crt"`)
		assert.Contains(t, hcl, `cert_path   = "/etc/etcd-pki/client.crt"`)
		assert.Contains(t, hcl, `key_path    = "/etc/etcd-pki/client.key"`)
	})
}

func TestGenEtcdPKIRenamesIntoPlace(t *testing.T) {
	require.NoError(t, cubeSettings.LoadMap(etcdPKITestSettings))

	saved := util.EtcdPKIDir
	t.Cleanup(func() { util.EtcdPKIDir = saved })
	util.EtcdPKIDir = filepath.Join(t.TempDir(), "etcd-pki")

	require.NoError(t, genEtcdPKI())

	_, err := os.Stat(util.EtcdCACertFile())
	assert.NoError(t, err)
	_, err = os.Stat(util.EtcdPKIDir + ".new")
	assert.True(t, os.IsNotExist(err), "no staging dir left behind")
}

func TestEtcdPKICoversControl(t *testing.T) {
	saved := util.EtcdPKIDir
	t.Cleanup(func() { util.EtcdPKIDir = saved })
	util.EtcdPKIDir = filepath.Join(t.TempDir(), "pki")

	require.NoError(t, cubeSettings.LoadMap(etcdPKITestSettings))
	require.NoError(t, genEtcdPKIInto(util.EtcdPKIDir))

	assert.NoError(t, util.EtcdMemberCertCovers("10.32.10.142", "sky142"), "a member of the control group")
	assert.NoError(t, util.EtcdMemberCertCovers("127.0.0.1", "localhost", "10.32.10.140"), "loopback and the VIP")

	err := util.EtcdMemberCertCovers("10.32.10.144", "sky144")
	if assert.Error(t, err, "a control node added after signing") {
		assert.Contains(t, err.Error(), "10.32.10.144")
		assert.Contains(t, err.Error(), "sky144")
	}
}

func TestResignEtcdMember(t *testing.T) {
	savedDir, savedBackup := util.EtcdPKIDir, etcdCertsBackupDir
	t.Cleanup(func() { util.EtcdPKIDir, etcdCertsBackupDir = savedDir, savedBackup })
	tmp := t.TempDir()
	util.EtcdPKIDir = filepath.Join(tmp, "pki")
	etcdCertsBackupDir = filepath.Join(tmp, "backup")

	require.NoError(t, cubeSettings.LoadMap(etcdPKITestSettings))
	require.NoError(t, genEtcdPKIInto(util.EtcdPKIDir))
	read := func(name string) []byte {
		b, err := os.ReadFile(filepath.Join(util.EtcdPKIDir, name))
		require.NoError(t, err)
		return b
	}
	caBefore, clientBefore, memberBefore := read("ca.crt"), read("client.crt"), read("member.crt")

	// a fourth control node joins the group
	grown := map[string]string{}
	for k, v := range etcdPKITestSettings {
		grown[k] = v
	}
	grown["cubesys.control.addrs"] += ",10.32.10.144"
	grown["cubesys.control.hosts"] += ",sky144"
	require.NoError(t, cubeSettings.LoadMap(grown))
	require.Error(t, util.EtcdMemberCertCovers("10.32.10.144", "sky144"))

	backup, err := resignEtcdMember()
	require.NoError(t, err)

	assert.NoError(t, util.EtcdMemberCertCovers("10.32.10.144", "sky144"))
	assert.NoError(t, verifyCertCoversControlGroup(util.EtcdMemberCertFile()))
	assert.Equal(t, caBefore, read("ca.crt"), "CA kept")
	assert.Equal(t, clientBefore, read("client.crt"), "client certificate kept")
	assert.NotEqual(t, memberBefore, read("member.crt"))

	ca := readTestCert(t, util.EtcdCACertFile())
	pool := x509.NewCertPool()
	pool.AddCert(ca)
	_, err = readTestCert(t, util.EtcdMemberCertFile()).Verify(x509.VerifyOptions{Roots: pool, DNSName: "10.32.10.144"})
	assert.NoError(t, err, "signed by the same CA")
	_, err = tls.LoadX509KeyPair(util.EtcdMemberCertFile(), util.EtcdMemberKeyFile())
	assert.NoError(t, err, "new key matches new certificate")
	fi, err := os.Stat(util.EtcdMemberKeyFile())
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0600), fi.Mode().Perm())

	saved, err := os.ReadFile(filepath.Join(backup, "member.crt"))
	require.NoError(t, err)
	assert.Equal(t, memberBefore, saved, "previous certificate backed up")

	entries, err := os.ReadDir(util.EtcdPKIDir)
	require.NoError(t, err)
	assert.Len(t, entries, 7, "no temp file left behind")
}

func TestResignEtcdMemberRefusesBadCA(t *testing.T) {
	savedDir, savedBackup := util.EtcdPKIDir, etcdCertsBackupDir
	t.Cleanup(func() { util.EtcdPKIDir, etcdCertsBackupDir = savedDir, savedBackup })
	tmp := t.TempDir()
	util.EtcdPKIDir = filepath.Join(tmp, "pki")
	etcdCertsBackupDir = filepath.Join(tmp, "backup")

	require.NoError(t, cubeSettings.LoadMap(etcdPKITestSettings))
	require.NoError(t, genEtcdPKIInto(util.EtcdPKIDir))
	before, _ := os.ReadFile(util.EtcdMemberCertFile())
	require.NoError(t, os.WriteFile(util.EtcdCAKeyFile(), []byte("garbage"), 0600))

	_, err := resignEtcdMember()
	assert.Error(t, err)
	after, _ := os.ReadFile(util.EtcdMemberCertFile())
	assert.Equal(t, before, after, "member certificate untouched")
}
