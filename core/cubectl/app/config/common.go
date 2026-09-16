package config

import (
	"cubectl/util"
	"io/ioutil"
	"net"
	"os"
	"strings"

	"github.com/pkg/errors"
	"go.uber.org/zap"

	cubeSettings "cubectl/util/settings"
)

const (
	mysqlSockFile = "/var/lib/mysql/mysql.sock"
	mysqlPort     = 3306
	certsDir      = "/var/www/certs/"
	keyFile       = certsDir + "/server.key"
	certFile      = certsDir + "/server.cert"
	certKeyFile   = certsDir + "/server.pem"
	sansConfFile  = "/tmp/openssl-sans.cnf"

	terraformWorkDir   = "/var/lib/terraform/"
	terraformStateFile = terraformWorkDir + "/terraform.tfstate"
)

func getIfaceIP(name string) (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}

	for _, i := range ifaces {
		if i.Name == name {
			addrs, err := i.Addrs()
			if err != nil {
				return "", err
			}

			for _, addr := range addrs {
				var ip net.IP
				switch v := addr.(type) {
				case *net.IPNet:
					ip = v.IP
					// case *net.IPAddr:
					//     ip = v.IP
				}

				return ip.String(), nil
			}
		}
	}

	return "", nil
}

// buildCertSANs assembles the subjectAltName argument for the cluster's self-signed
// certificate.
//
// Every control node has to be covered, not just the VIP: AMQP clients address the
// nodes directly (RabbitMqServers() iterates cubesys.control.addrs), so a VIP-only
// SAN makes the TLS handshake fail against every node. The certificate is signed once
// on the master control node and rsynced to the rest, so one certificate has to carry
// all of them.
//
// Empty values are dropped rather than emitted as a bare "IP:" - openssl rejects the
// whole extension with "invalid null value", and cubesys.control.addrs is absent
// altogether on a non-HA node.
func buildCertSANs() string {
	var sans []string
	seen := map[string]bool{}

	add := func(kind, value string) {
		value = strings.TrimSpace(value)
		if value == "" {
			return
		}

		entry := kind + ":" + value
		if seen[entry] {
			return
		}
		seen[entry] = true

		sans = append(sans, entry)
	}

	add("DNS", "localhost")
	add("DNS", "cube-controller")
	add("DNS", cubeSettings.GetController())
	add("IP", "127.0.0.1")
	add("IP", cubeSettings.GetControllerIp())

	if cubeSettings.IsHA() {
		for _, addr := range cubeSettings.GetControlGroupIPs() {
			add("IP", addr)
		}
		for _, host := range cubeSettings.GetControlGroupHosts() {
			add("DNS", host)
		}
	}

	return "subjectAltName=" + strings.Join(sans, ",")
}

func genSelfSignCerts() error {
	os.MkdirAll(certsDir, 0755)

	// 	sansStr := `
	// [req]
	// distinguished_name=req
	// [san]
	// subjectAltName=DNS:localhost,DNS:cube-controller,IP:127.0.0.1` + ",IP:" + cubeSettings.GetControllerIp()

	// 	if err := ioutil.WriteFile(sansConfFile, []byte(sansStr), 0644); err != nil {
	// 		return errors.WithStack(err)
	// 	}

	if _, outErr, err := util.ExecCmd("openssl",
		"req", "-x509", "-newkey", "rsa:2048", "-nodes",
		"-keyout", keyFile,
		"-out", certFile,
		"-days", "3650",
		"-subj", "/CN="+cubeSettings.GetController(),
		"-addext", buildCertSANs(),
		// "-addext", "basicConstraints=CA:TRUE,pathlen:0",
		// "-extensions", "san",
		// "-config", sansConfFile,
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	if _, outErr, err := util.ExecShf("cat %s %s | tee %s", certFile, keyFile, certKeyFile); err != nil {
		return errors.Wrap(err, outErr)
	}

	if err := os.Chmod(keyFile, 0644); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func genSshKeys() error {
	os.MkdirAll("/root/.ssh/", 0755)
	if _, outErr, err := util.ExecCmd("ssh-keygen", "-f", "/root/.ssh/id_rsa", "-N", ""); err != nil {
		return errors.Wrap(err, outErr)
	}
	if _, outErr, err := util.ExecCmd("cp", "-f", "/root/.ssh/id_rsa.pub", "/root/.ssh/authorized_keys"); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

func terraformExec(cmd string, mod string, vars []string, varFiles []string) error {
	args := []string{
		cmd, "-auto-approve",
		"-target=module." + mod,
	}

	if cmd == "destroy" {
		args = append(args, "-refresh=false")
	}

	for _, v := range vars {
		args = append(args, "-var", v)
	}

	for _, vf := range varFiles {
		args = append(args, "-var-file="+vf)
	}

	if err := util.Retry(
		func() error {
			if _, outErr, err := util.ExecCmd("terraform-cube.sh", args...); err != nil {
				return errors.Wrap(err, outErr)
			}

			return nil
		},
		3,
	); err != nil {
		return errors.WithStack(err)
	}
	zap.L().Info("Terraform applied", zap.String("command", cmd), zap.String("module", mod))

	// if err := terraformPullState(); err != nil {
	// 	return errors.WithStack(err)
	// }

	// if _, err := util.LoadClusterSettings(); err == nil {
	// 	if err := terraformSyncState(); err != nil {
	// 		return errors.WithStack(err)
	// 	}
	// }

	return nil
}

func terraformImport(resouce string, id string, vars ...string) error {
	args := []string{
		"import", resouce, id,
	}

	for _, v := range vars {
		args = append(args, "-var", v)
	}

	if err := util.Retry(
		func() error {
			if _, outErr, err := util.ExecCmd("terraform-cube.sh", args...); err != nil {
				return errors.Wrap(err, outErr)
			}

			return nil
		},
		3,
	); err != nil {
		return errors.WithStack(err)
	}
	zap.L().Info("Terraform imported", zap.String("resource", resouce), zap.String("id", id))

	// if err := terraformPullState(); err != nil {
	// 	return errors.WithStack(err)
	// }

	// if _, err := util.LoadClusterSettings(); err == nil {
	// 	if err := terraformSyncState(); err != nil {
	// 		return errors.WithStack(err)
	// 	}
	// }

	return nil
}

func terraformInitBackend() error {
	// Init terraform with etcd backend
	_, _, err := util.ExecCmd("terraform-cube.sh",
		"init",
		"-plugin-dir=.terraform/providers/",
		"-reconfigure",
	)

	return err
}

func terraformPullState() error {
	if out, outErr, err := util.ExecCmd("terraform-cube.sh",
		"state", "pull",
	); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		if err := ioutil.WriteFile(terraformStateFile, []byte(out), 0644); err != nil {
			return errors.WithStack(err)
		}
	}

	zap.L().Info("Terraform state pulled")

	return nil
}

func terraformPushState() error {
	if _, outErr, err := util.ExecCmd("terraform-cube.sh",
		"state", "push", terraformStateFile,
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	zap.L().Info("Terraform state pushed")

	return nil
}

func terraformSyncState() error {
	if _, outErr, err := util.ExecCmd("cubectl", "node", "rsync",
		terraformWorkDir,
		"--role=control",
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	zap.L().Info("Terraform state synced to control nodes")

	return nil
}
