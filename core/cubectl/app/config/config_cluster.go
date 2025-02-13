package config

import (
	"os"

	"github.com/pkg/errors"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	revisionFile    = "/etc/revision"
	rejoinMarker    = "/run/control_rejoin"
	migrationMarker = "/run/cube_migration"
)

func isJoined() bool {
	if _, err := os.Stat(revisionFile); os.IsNotExist(err) {
		return false
	}

	return true
}

func isMigration() bool {
	if _, err := os.Stat(migrationMarker); err == nil {
		return true
	}

	return false
}

func commitCluster() error {
	zap.S().Debugf("Executing commitCluster()")

	if cubeSettings.GetRole() == "undef" {
		return nil
	}

	// if !bootstrap {
	// 	return nil
	// }

	if isJoined() {
		zap.S().Infof("Already joined cube cluster")
		if _, outErr, err := util.ExecCmd("cubectl", "this-node", "start"); err != nil {
			return errors.Wrap(err, outErr)
		}
	} else {
		if _, err := os.Stat(rejoinMarker); os.IsNotExist(err) && cubeSettings.IsMasterControl() {
			zap.S().Infof("Creating a new cluster")

			if _, outErr, err := util.ExecCmd("cubectl", "this-node", "new"); err != nil {
				return errors.Wrap(err, outErr)
			}

			if _, err := os.Stat(certFile); os.IsNotExist(err) {
				if err := genSelfSignCerts(); err != nil {
					return errors.WithStack(err)
				}

				zap.L().Info("Self-signed cert generated")
			} else {
				zap.L().Info("Self-signed cert existed")
			}

			// Restore terraform state for cluster IP changes
			if _, err := os.Stat(terraformStateFile); err == nil {
				if err := terraformPushState(); err != nil {
					return errors.WithStack(err)
				}
			}

		} else {
			if _, err := os.Stat(rejoinMarker); err == nil {
				if _, _, err := util.ExecCmd("cubectl", "node", "remove", cubeSettings.GetHostname()); err != nil {
					//return errors.Wrap(err, outErr)
					zap.L().Warn("Failed to remove previous node for rejoining", zap.Error(err))
				} else {
					zap.L().Info("Previous node removed")
				}
			}

			zap.S().Infof("Joining an existing cluster")
			if _, outErr, err := util.ExecCmd("cubectl", "this-node", "join"); err != nil {
				return errors.Wrap(err, outErr)
			}

			if _, _, err := util.ExecCmd("cubectl", "node", "rsync",
				cubeSettings.GetControllerIp()+":"+certsDir,
			); err != nil {
				return errors.WithStack(err)
			}
			zap.L().Info("Cert data synced from cube-controller")

			if _, outErr, err := util.ExecCmd("cubectl", "node", "rsync",
				cubeSettings.GetControllerIp()+":"+terraformWorkDir,
			); err != nil {
				return errors.Wrap(err, outErr)
			}
			zap.L().Info("Terraform data synced from cube-controller")
		}

		// if cubeSettings.IsRole(util.ROLE_CONTROL) {
		// 	// Ingore error
		// 	if err := terraformInitBackend(); err != nil {
		// 		zap.L().Info(err.Error())
		// 	}
		// 	zap.L().Info("Terraform init with etcd backend")
		// }

	}

	return nil
}

func resetCluster() error {
	if resetOpts.hard {
		os.Remove(terraformStateFile)
	}
	// else {
	// 	if cubeSettings.IsMasterControl() {
	// 		if err := terraformPullState(); err != nil {
	// 			zap.S().Warn(errors.WithStack(err))
	// 		}
	// 	}
	// }

	os.RemoveAll(certsDir)

	if _, _, err := util.ExecCmd("cubectl", "this-node", "reset"); err != nil {
		zap.S().Warn(err)
	}

	return nil
}

func init() {
	m := NewModule("cluster")
	m.commitFunc = commitCluster
	m.resetFunc = resetCluster
}
