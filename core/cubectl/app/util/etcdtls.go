package util

import "path/filepath"

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
)

func EtcdCACertFile() string       { return filepath.Join(EtcdPKIDir, "ca.crt") }
func EtcdCAKeyFile() string        { return filepath.Join(EtcdPKIDir, "ca.key") }
func EtcdMemberCertFile() string   { return filepath.Join(EtcdPKIDir, "member.crt") }
func EtcdMemberKeyFile() string    { return filepath.Join(EtcdPKIDir, "member.key") }
func EtcdClientCertFile() string   { return filepath.Join(EtcdPKIDir, "client.crt") }
func EtcdClientKeyFile() string    { return filepath.Join(EtcdPKIDir, "client.key") }
func EtcdTerraformBackend() string { return filepath.Join(EtcdPKIDir, "terraform-backend.hcl") }
