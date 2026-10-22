package cmd

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

// useTestEtcdPKI points the etcd PKI and compat marker at a temp dir for one test and
// returns a function that puts the node in the given mode. One self-signed certificate
// stands in for CA and client: enough for the client config to load.
func useTestEtcdPKI(t *testing.T) func(mode util.EtcdTLSMode) {
	t.Helper()
	savedDir, savedMarker := util.EtcdPKIDir, util.EtcdTLSCompatMarker
	t.Cleanup(func() { util.EtcdPKIDir, util.EtcdTLSCompatMarker = savedDir, savedMarker })

	dir := t.TempDir()
	util.EtcdPKIDir = filepath.Join(dir, "etcd-pki")
	util.EtcdTLSCompatMarker = filepath.Join(dir, "etcd_tls_compat")

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: util.EtcdClientCN},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	require.NoError(t, err)
	crt := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	k := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})

	return func(mode util.EtcdTLSMode) {
		os.RemoveAll(util.EtcdPKIDir)
		os.Remove(util.EtcdTLSCompatMarker)
		if mode == util.EtcdTLSPlain {
			return
		}
		require.NoError(t, os.MkdirAll(util.EtcdPKIDir, 0700))
		require.NoError(t, os.WriteFile(util.EtcdCACertFile(), crt, 0644))
		require.NoError(t, os.WriteFile(util.EtcdClientCertFile(), crt, 0644))
		require.NoError(t, os.WriteFile(util.EtcdClientKeyFile(), k, 0600))
		if mode == util.EtcdTLSCompat {
			require.NoError(t, os.WriteFile(util.EtcdTLSCompatMarker, nil, 0644))
		}
		require.Equal(t, mode, util.GetEtcdTLSMode())
	}
}

func TestGetEtcdClientTLS(t *testing.T) {
	setMode := useTestEtcdPKI(t)
	addrs := []string{"10.0.0.10", "10.0.0.11"}

	t.Run("Plain", func(t *testing.T) {
		setMode(util.EtcdTLSPlain)
		cfg, err := etcdClientConfig(addrs...)
		require.NoError(t, err)
		assert.Equal(t, []string{"10.0.0.10:12379", "10.0.0.11:12379"}, cfg.Endpoints)
		assert.Nil(t, cfg.TLS)
	})

	t.Run("Compat", func(t *testing.T) {
		setMode(util.EtcdTLSCompat)
		cfg, err := etcdClientConfig(addrs...)
		require.NoError(t, err)
		assert.Equal(t, []string{"10.0.0.10:12379", "10.0.0.11:12379"}, cfg.Endpoints)
		assert.Nil(t, cfg.TLS, "compat clients stay on http")
	})

	t.Run("Enforce", func(t *testing.T) {
		setMode(util.EtcdTLSEnforce)
		cfg, err := etcdClientConfig(addrs...)
		require.NoError(t, err)
		assert.Equal(t, []string{"https://10.0.0.10:12379", "https://10.0.0.11:12379"}, cfg.Endpoints)
		if assert.NotNil(t, cfg.TLS) {
			assert.Len(t, cfg.TLS.Certificates, 1)
			assert.NotNil(t, cfg.TLS.RootCAs)
		}
	})

	t.Run("DefaultsToLocalhost", func(t *testing.T) {
		setMode(util.EtcdTLSEnforce)
		cfg, err := etcdClientConfig()
		require.NoError(t, err)
		assert.Equal(t, []string{"https://localhost:12379"}, cfg.Endpoints)
	})

	t.Run("EnforceWithoutClientKey", func(t *testing.T) {
		setMode(util.EtcdTLSEnforce)
		os.Remove(util.EtcdClientKeyFile())
		_, err := etcdClientConfig(addrs...)
		assert.Error(t, err, "does not fall back to http")
	})
}

func TestEtcdMemberAddPeerURLScheme(t *testing.T) {
	assert.Equal(t, "http://10.0.0.11:12380", etcdPeerURL(util.EtcdTLSPlain, "10.0.0.11"))
	assert.Equal(t, "http://10.0.0.11:12380", etcdPeerURL(util.EtcdTLSCompat, "10.0.0.11"))
	assert.Equal(t, "https://10.0.0.11:12380", etcdPeerURL(util.EtcdTLSEnforce, "10.0.0.11"))
}

func TestEtcdConfig(t *testing.T) {
	useTestEtcdPKI(t)
	nonHA := map[string]string{
		"net.hostname":       "cc1",
		"cubesys.seed":       "seed",
		"cubesys.management": "eth0",
		"net.if.addr.eth0":   "10.0.0.11",
	}
	ha := map[string]string{
		"net.hostname":        "cc1",
		"cubesys.seed":        "seed",
		"cubesys.management":  "eth0",
		"net.if.addr.eth0":    "10.0.0.11",
		"cubesys.ha":          "true",
		"cubesys.control.vip": "10.0.0.10",
	}
	initCluster := "cc1=http://10.0.0.11:12380,cc2=http://10.0.0.12:12380"

	t.Run("Plain", func(t *testing.T) {
		// what writeEtcdConfig wrote before etcd had a TLS mode, key for key
		require.NoError(t, cubeSettings.LoadMap(nonHA))
		assert.Equal(t, map[string]interface{}{
			"name":                        "cc1",
			"data-dir":                    etcdDataDir,
			"listen-client-urls":          "http://127.0.0.1:12379,http://10.0.0.11:12379",
			"listen-peer-urls":            "http://10.0.0.11:12380",
			"advertise-client-urls":       "http://10.0.0.11:12379",
			"initial-advertise-peer-urls": "http://10.0.0.11:12380",
			"initial-cluster-token":       "seed",
			"initial-cluster-state":       "existing",
			"initial-cluster":             initCluster,
		}, etcdConfigValues(util.EtcdTLSPlain, "existing", initCluster))

		require.NoError(t, cubeSettings.LoadMap(ha))
		conf := etcdConfigValues(util.EtcdTLSPlain, "new", "")
		assert.Equal(t, "http://127.0.0.1:12379,http://10.0.0.11:12379,http://10.0.0.10:12379", conf["listen-client-urls"])
		assert.NotContains(t, conf, "initial-cluster")
		assert.Len(t, conf, 8)
	})

	t.Run("Compat", func(t *testing.T) {
		require.NoError(t, cubeSettings.LoadMap(ha))
		conf := etcdConfigValues(util.EtcdTLSCompat, "existing", initCluster)
		assert.Equal(t, "http://127.0.0.1:12379,https://127.0.0.1:12379,"+
			"http://10.0.0.11:12379,https://10.0.0.11:12379,"+
			"http://10.0.0.10:12379,https://10.0.0.10:12379", conf["listen-client-urls"])
		assert.Equal(t, "http://10.0.0.11:12380", conf["listen-peer-urls"], "one peer listener: http")
		assert.Equal(t, "http://10.0.0.11:12379", conf["advertise-client-urls"])
		assert.Equal(t, "http://10.0.0.11:12380", conf["initial-advertise-peer-urls"])
		tlsConf := map[string]interface{}{
			"cert-file":       util.EtcdMemberCertFile(),
			"key-file":        util.EtcdMemberKeyFile(),
			"trusted-ca-file": util.EtcdCACertFile(),
		}
		assert.Equal(t, tlsConf, conf["client-transport-security"], "no client-cert-auth")
		assert.Equal(t, tlsConf, conf["peer-transport-security"], "can dial https peers, does not check")
	})

	t.Run("Enforce", func(t *testing.T) {
		require.NoError(t, cubeSettings.LoadMap(ha))
		conf := etcdConfigValues(util.EtcdTLSEnforce, "new", "")
		assert.Equal(t, "https://127.0.0.1:12379,https://10.0.0.11:12379,https://10.0.0.10:12379", conf["listen-client-urls"])
		assert.Equal(t, "https://10.0.0.11:12380", conf["listen-peer-urls"])
		assert.Equal(t, "https://10.0.0.11:12379", conf["advertise-client-urls"])
		assert.Equal(t, "https://10.0.0.11:12380", conf["initial-advertise-peer-urls"])
		assert.Equal(t, map[string]interface{}{
			"cert-file":        util.EtcdMemberCertFile(),
			"key-file":         util.EtcdMemberKeyFile(),
			"trusted-ca-file":  util.EtcdCACertFile(),
			"client-cert-auth": true,
		}, conf["client-transport-security"])
		assert.Equal(t, map[string]interface{}{
			"cert-file":        util.EtcdMemberCertFile(),
			"key-file":         util.EtcdMemberKeyFile(),
			"trusted-ca-file":  util.EtcdCACertFile(),
			"client-cert-auth": true,
			"allowed-cn":       []string{util.EtcdMemberCN},
		}, conf["peer-transport-security"])
	})
}
