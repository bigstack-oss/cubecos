package config

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"path"

	"github.com/pkg/errors"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	keycloakDbName           = "keycloak"
	keycloakDbUser           = "keycloak"
	keycloakDbPassword       = "password"
	keycloakSamlMetadataFile = "/etc/keycloak/saml-metadata.xml"
	keycloakDataDir          = "/opt/keycloak/"
)

func keycloakCheckEndpoint() error {
	url := fmt.Sprintf("https://%s:%d%s", cubeSettings.GetControllerIp(), k3sIngressHttpsPort, "/auth/realms/master")
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return errors.WithStack(err)
	}

	if err := util.Retry(
		func() error {
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				return err
			}
			defer resp.Body.Close()

			zap.S().Debug(resp)

			if resp.StatusCode != 200 {
				return fmt.Errorf("not ready. StatusCode: %d", resp.StatusCode)
			}

			return nil
		},
		15,
	); err != nil {
		return errors.WithStack(err)
	}

	zap.L().Info("Keycloak endpoint ready")

	return nil
}

func keycloakDeploy() error {
	if err := k3sCheckReplicas("statefulset.apps/keycloak", "keycloak"); err != nil || commitOpts.force || isMigration() {
		// Create keycloak db on mysql
		if err := terraformExec("apply", "mysql", "mysql_dbname="+keycloakDbName); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		nodeCount, err := k3sGetNodeCounts()
		if err != nil {
			return errors.WithStack(err)
		}

		if err := util.Retry(
			func() error {
				if _, outErr, err := util.ExecShf("helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install keycloak %s -n keycloak --create-namespace -f %s --set replicas=%d",
					keycloakDataDir+"/keycloak-*.tgz", keycloakDataDir+"/chart-values.yaml", nodeCount,
				); err != nil {
					return errors.Wrap(err, outErr)
				}
				zap.L().Info("Keycloak release upgraded")

				return nil
			},
			3,
		); err != nil {
			return errors.WithStack(err)
		}

		if err := k3sWatchRollOut("statefulset.apps/keycloak", "keycloak", "3m"); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		if err := keycloakCheckEndpoint(); err != nil {
			return errors.WithStack(err)
		}

		// Create default cube groups
		if err := terraformExec("apply", "keycloak"); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}
	}

	return nil
}

func keycloakGetSamlMetadata() error {
	if _, err := os.Stat(keycloakSamlMetadataFile); os.IsNotExist(err) || commitOpts.force || isMigration() {
		os.MkdirAll(path.Dir(keycloakSamlMetadataFile), 0755)

		if err := keycloakCheckEndpoint(); err != nil {
			return errors.WithStack(err)
		}

		if err := util.Retry(
			func() error {
				// Must use control vip in curl because the content of saml metadata will honor it as ip/hostname
				out, outErr, err := util.ExecShf("curl -k https://%s:%d/auth/realms/master/protocol/saml/descriptor", cubeSettings.GetControllerIp(), k3sIngressHttpsPort)
				if err != nil {
					return errors.Wrap(err, outErr)
				}

				if out == "" {
					return fmt.Errorf("error retrieving %s", keycloakSamlMetadataFile)
				}

				if err = ioutil.WriteFile(keycloakSamlMetadataFile, []byte(out), 0644); err != nil {
					return errors.WithStack(err)
				}

				return nil
			},
			120,
		); err != nil {
			return err
		}
	}

	return nil
}

func commitKeycloak() error {
	if cubeSettings.GetRole() == "undef" {
		return nil
	}

	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	if err := keycloakDeploy(); err != nil {
		return errors.WithStack(err)
	}

	if err := keycloakGetSamlMetadata(); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func resetKeycloak() error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	os.RemoveAll(keycloakSamlMetadataFile)

	if err := terraformExec("destroy", "keycloak"); err != nil {
		zap.S().Warn(errors.WithStack(err))
	}

	if _, outErr, err := util.ExecCmd("helm",
		"--kubeconfig=/etc/rancher/k3s/k3s.yaml",
		"uninstall",
		"keycloak", "-n", "keycloak",
	); err != nil {
		zap.S().Warn(errors.Wrap(err, outErr))
	}
	zap.L().Info("Keycloak release uninstalled")

	if resetOpts.hard {
		if err := terraformExec("destroy", "mysql", "mysql_dbname="+keycloakDbName); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		if err := k3sDeleteNamespace("keycloak"); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}
	}

	return nil
}

func statusKeycloak() error {
	if out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", "all", "-n", "keycloak",
		"-o", "wide",
	); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		fmt.Println(out)
	}

	return nil
}

func checkKeycloak() error {
	if err := k3sWatchRollOut("statefulset.apps/keycloak", "keycloak", "1s"); err != nil {
		return errors.WithStack(err)
	}

	nodeCount, err := k3sGetNodeCounts()
	if err != nil {
		return errors.WithStack(err)
	}

	replicaCount, err := k3sGetReadyReplicas("statefulset.apps/keycloak", "keycloak")
	if err != nil {
		return errors.WithStack(err)
	}

	if nodeCount != replicaCount {
		return fmt.Errorf("control node count: %d doesn't match replica count: %d", nodeCount, replicaCount)
	}

	return nil
}

func repairKeycloak() error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"delete", "pods", "--all", "-n", "keycloak",
		"--grace-period=0", "--force",
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	if err := k3sWatchRollOut("statefulset.apps/keycloak", "keycloak", "3m"); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func init() {
	m := NewModule("keycloak")
	m.commitFunc = commitKeycloak
	m.resetFunc = resetKeycloak
	m.statusFunc = statusKeycloak
	m.checkFunc = checkKeycloak
	m.repairFunc = repairKeycloak
}
