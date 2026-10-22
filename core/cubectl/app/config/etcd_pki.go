package config

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pkg/errors"

	"cubectl/util"
)

// Same lifetime as the cluster's server.cert; nothing in cube rotates either automatically.
const etcdCertDays = 3650

// genEtcdPKI signs the etcd CA, the member certificate and the client certificate into
// util.EtcdPKIDir. It runs on the master control node only; every other node pulls the
// directory from there.
//
// The files are signed into a sibling directory and moved into place with one rename: the
// TLS mode keys off the CA certificate being present, so a half-written directory must
// never be visible under the real name.
func genEtcdPKI() error {
	staging := filepath.Clean(util.EtcdPKIDir) + ".new"
	os.RemoveAll(staging)

	if err := genEtcdPKIInto(staging); err != nil {
		os.RemoveAll(staging)
		return err
	}

	return errors.WithStack(os.Rename(staging, util.EtcdPKIDir))
}

// genEtcdPKIInto writes a fresh CA, member and client pair, and the terraform backend
// override that points at them, into dir.
//
// One member certificate serves every etcd member, as server and as peer client, so its
// SAN is the whole control group (buildCertSANs). Its CN is what the peer listener's
// allowed-cn admits; the client certificate carries a different CN so that holding it
// - every node does, compute included - does not open the peer port.
//
// The client certificate has no SAN: it is shared by every node and names none of them.
func genEtcdPKIInto(dir string) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return errors.WithStack(err)
	}

	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return errors.WithStack(err)
	}

	caTmpl := etcdCertTemplate(util.EtcdCACN)
	caTmpl.IsCA = true
	caTmpl.BasicConstraintsValid = true
	caTmpl.MaxPathLenZero = true
	caTmpl.KeyUsage = x509.KeyUsageCertSign | x509.KeyUsageCRLSign

	caDER, err := x509.CreateCertificate(rand.Reader, caTmpl, caTmpl, &caKey.PublicKey, caKey)
	if err != nil {
		return errors.WithStack(err)
	}
	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		return errors.WithStack(err)
	}

	if err := writeEtcdPair(dir, "ca", caDER, caKey); err != nil {
		return err
	}

	if err := signEtcdMemberInto(dir, caCert, caKey); err != nil {
		return err
	}

	clientTmpl := etcdCertTemplate(util.EtcdClientCN)
	clientTmpl.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
	if err := signEtcdLeafInto(dir, "client", clientTmpl, caCert, caKey); err != nil {
		return err
	}

	return writeEtcdTerraformBackend(dir)
}

// signEtcdMemberInto signs the member certificate over the current control group.
func signEtcdMemberInto(dir string, caCert *x509.Certificate, caKey *rsa.PrivateKey) error {
	tmpl := etcdCertTemplate(util.EtcdMemberCN)
	tmpl.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}
	tmpl.DNSNames, tmpl.IPAddresses = parseCertSANs(buildCertSANs())

	return signEtcdLeafInto(dir, "member", tmpl, caCert, caKey)
}

func signEtcdLeafInto(dir string, name string, tmpl *x509.Certificate, caCert *x509.Certificate, caKey *rsa.PrivateKey) error {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return errors.WithStack(err)
	}

	tmpl.KeyUsage = x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment
	der, err := x509.CreateCertificate(rand.Reader, tmpl, caCert, &key.PublicKey, caKey)
	if err != nil {
		return errors.WithStack(err)
	}

	return writeEtcdPair(dir, name, der, key)
}

func etcdCertTemplate(cn string) *x509.Certificate {
	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 127))
	// An hour back, so a node whose clock trails the master's by a little does not see
	// the certificate as not yet valid.
	now := time.Now().Add(-time.Hour)

	return &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: cn},
		NotBefore:    now,
		NotAfter:     now.AddDate(0, 0, etcdCertDays),
	}
}

// writeEtcdPair writes <name>.crt world-readable and <name>.key readable by root only.
func writeEtcdPair(dir string, name string, der []byte, key *rsa.PrivateKey) error {
	crt := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	if err := ioutil.WriteFile(filepath.Join(dir, name+".crt"), crt, 0644); err != nil {
		return errors.WithStack(err)
	}

	k := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	if err := ioutil.WriteFile(filepath.Join(dir, name+".key"), k, 0600); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

// writeEtcdTerraformBackend writes the override terraform-action.sh hands to `terraform
// init -backend-config` once the cluster enforces TLS. main.tf keeps its plain endpoint:
// /var/lib/terraform is rsynced between control nodes after every apply, and during a
// rolling upgrade a node still on plain etcd must not be handed an https backend.
func writeEtcdTerraformBackend(dir string) error {
	hcl := fmt.Sprintf(`endpoints   = ["https://127.0.0.1:%d"]
cacert_path = %q
cert_path   = %q
key_path    = %q
`, util.EtcdClientPort, util.EtcdCACertFile(), util.EtcdClientCertFile(), util.EtcdClientKeyFile())

	return errors.WithStack(ioutil.WriteFile(filepath.Join(dir, filepath.Base(util.EtcdTerraformBackend())), []byte(hcl), 0644))
}

// parseCertSANs splits buildCertSANs() output into what an x509 template takes.
func parseCertSANs(sans string) ([]string, []net.IP) {
	var (
		dns []string
		ips []net.IP
	)

	for _, entry := range strings.Split(strings.TrimPrefix(sans, "subjectAltName="), ",") {
		kind, value, _ := strings.Cut(entry, ":")
		switch kind {
		case "DNS":
			dns = append(dns, value)
		case "IP":
			if ip := net.ParseIP(value); ip != nil {
				ips = append(ips, ip)
			}
		}
	}

	return dns, ips
}
