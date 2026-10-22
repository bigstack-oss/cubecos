package util

import (
	"crypto/tls"
	"crypto/x509"
	"io/ioutil"
	"os"
	"path/filepath"

	"github.com/pkg/errors"
)

// cube's own etcd (client 12379, peer 12380) authenticates clients and peers with
// certificates from a CA of its own, kept apart from /var/www/certs so that replacing the
// web certificate - the FQDN procedure swaps in the customer's chain - never touches it.
//
// The directory sits outside /etc/etcd on purpose: `cubectl this-node reset` removes all
// of /etc/etcd, and health_etcd_repair follows it with a join that needs a client
// certificate to add the member back.
const (
	EtcdClientPort = 12379

	EtcdCACN     = "cube-etcd-ca"
	EtcdMemberCN = "etcd-member"
	EtcdClientCN = "etcd-client"
)

// Variables rather than constants so tests can point them at a temporary directory.
var (
	EtcdPKIDir = "/etc/etcd-pki"

	// Present while an upgraded cluster has not finished its rolling upgrade: members keep
	// serving plain http next to https and every client stays on http, because the nodes
	// not rolled yet only speak http. The ladder at the end of the roll removes it.
	EtcdTLSCompatMarker = "/etc/appliance/state/etcd_tls_compat"
)

func EtcdCACertFile() string       { return filepath.Join(EtcdPKIDir, "ca.crt") }
func EtcdCAKeyFile() string        { return filepath.Join(EtcdPKIDir, "ca.key") }
func EtcdMemberCertFile() string   { return filepath.Join(EtcdPKIDir, "member.crt") }
func EtcdMemberKeyFile() string    { return filepath.Join(EtcdPKIDir, "member.key") }
func EtcdClientCertFile() string   { return filepath.Join(EtcdPKIDir, "client.crt") }
func EtcdClientKeyFile() string    { return filepath.Join(EtcdPKIDir, "client.key") }
func EtcdTerraformBackend() string { return filepath.Join(EtcdPKIDir, "terraform-backend.hcl") }

type EtcdTLSMode int

const (
	// No PKI: http only, no certificates. A node that predates etcd TLS.
	EtcdTLSPlain EtcdTLSMode = iota
	// PKI and compat marker: members serve http and https, clients use http.
	EtcdTLSCompat
	// PKI, no marker: https only, clients and peers present certificates.
	EtcdTLSEnforce
)

func (m EtcdTLSMode) String() string {
	switch m {
	case EtcdTLSCompat:
		return "compat"
	case EtcdTLSEnforce:
		return "enforce"
	}
	return "plain"
}

// GetEtcdTLSMode reads the mode off disk on every call; the ladder changes it under
// running processes.
func GetEtcdTLSMode() EtcdTLSMode {
	if _, err := os.Stat(EtcdCACertFile()); err != nil {
		return EtcdTLSPlain
	}
	if _, err := os.Stat(EtcdTLSCompatMarker); err == nil {
		return EtcdTLSCompat
	}
	return EtcdTLSEnforce
}

// EtcdClientTLSConfig is what a client presents to etcd in enforce mode.
func EtcdClientTLSConfig() (*tls.Config, error) {
	cert, err := tls.LoadX509KeyPair(EtcdClientCertFile(), EtcdClientKeyFile())
	if err != nil {
		return nil, errors.WithStack(err)
	}

	ca, err := ioutil.ReadFile(EtcdCACertFile())
	if err != nil {
		return nil, errors.WithStack(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return nil, errors.Errorf("no certificate in %s", EtcdCACertFile())
	}

	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      pool,
		MinVersion:   tls.VersionTLS12,
	}, nil
}
