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
