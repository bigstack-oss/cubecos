package config

import (
	"cubectl/util"
	"io/ioutil"
	"net"
	"os"

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
		"-addext", "subjectAltName=DNS:localhost,DNS:cube-controller,IP:127.0.0.1,IP:"+cubeSettings.GetControllerIp(),
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

func terraformExec(cmd string, mod string, vars ...string) error {
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
