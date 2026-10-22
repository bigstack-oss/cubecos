package cmd

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

var ()

func runThisnodeStart(cmd *cobra.Command, args []string) error {
	if cubeSettings.IsRole(util.ROLE_CONTROL) {
		if _, err := refreshEtcdConfig(etcdConfigFile); err != nil {
			zap.S().Warnf("Failed to refresh etcd config: %v", err)
		}
		// Start etcd non-blocking, then wait (bounded) for it to serve, so
		// parallel node reboots form quorum instead of each blocking serially.
		if _, _, err := util.ExecCmd("systemctl", "start", "--no-block", "etcd"); err != nil {
			return errors.WithStack(err)
		}
		if err := waitEtcdHealthy(60 * time.Second); err != nil {
			startEtcdWatch()
			return errors.WithStack(err)
		}
	}

	if err := runTuningPull(nil, []string{}); err != nil {
		startEtcdWatch()
		return errors.WithStack(err)
	}

	if _, _, err := util.ExecCmd("systemctl", "start", "etcd-watch"); err != nil {
		return errors.WithStack(err)
	}

	// if err := etcdStart(); err != nil {
	// 	return fmt.Errorf("Failed to start ETCD: %v", err)
	// }

	//if err := runTuningApply(nil, []string{}); err != nil {
	//	return err
	//}

	//if _, _, err := cubeUtil.ExecCmd("/usr/sbin/hex_config", "bootstrap", "standalone-done"); err != nil {
	//	return err
	//}

	return nil
}

// startEtcdWatch starts the watcher even when etcd has no quorum yet (cold
// boot): it retries until etcd serves instead of staying stopped for good.
func startEtcdWatch() {
	if _, _, err := util.ExecCmd("systemctl", "start", "etcd-watch"); err != nil {
		zap.S().Warnf("Failed to start etcd-watch: %v", err)
	}
}

// runThisnodeEtcdRefresh brings the local etcd member in line with the node's etcd TLS
// mode and restarts it when it runs anything else. etcd_tls_ladder calls it on one control
// node at a time; it returns only once the member serves again, or fails.
//
// In enforce the member's peer URL moves to https first, while the member still answers
// on its current config. A restart is due when the config changed or when a member that
// should serve https does not: `this-node start` may have rewritten the config of an etcd
// that was already running.
func runThisnodeEtcdRefresh(cmd *cobra.Command, args []string) error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return fmt.Errorf("Can only be performed on control node")
	}

	mode := util.GetEtcdTLSMode()
	if mode == util.EtcdTLSEnforce {
		if err := etcdUpdateSelfPeerURL(); err != nil {
			return errors.WithStack(err)
		}
	}

	changed, err := refreshEtcdConfig(etcdConfigFile)
	if err != nil {
		return errors.WithStack(err)
	}

	if !changed && (mode == util.EtcdTLSPlain || etcdServesTLS()) {
		fmt.Printf("etcd already runs %s\n", mode)
		return nil
	}

	// blocks until the member reports ready (Type=notify); the bound only keeps a member
	// that cannot reach quorum from holding the caller forever
	if _, outErr, err := util.ExecCmd("timeout", "90", "systemctl", "restart", "etcd"); err != nil {
		return errors.Wrap(err, outErr)
	}
	if err := waitEtcdHealthy(60 * time.Second); err != nil {
		return errors.WithStack(err)
	}
	if mode != util.EtcdTLSPlain && !etcdServesTLS() {
		return errors.Errorf("etcd restarted in %s but does not serve https", mode)
	}

	fmt.Printf("etcd restarted in %s\n", mode)
	return nil
}

func runThisnodeNew(cmd *cobra.Command, args []string) error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return fmt.Errorf("Can only be performed on control node")
	}

	if err := writeEtcdConfig("new", ""); err != nil {
		return errors.WithStack(err)
	}

	if _, _, err := util.ExecCmd("systemctl", "start", "etcd"); err != nil {
		return errors.WithStack(err)
	}

	// if id, err := getSelfEtcdMemberID("localhost", cubeSettings.GetHostname()); err != nil {
	// 	return errors.WithStack(err)
	// } else {
	// 	if err := saveLocalMemberID(id); err != nil {
	// 		return errors.WithStack(err)
	// 	}
	// }

	if err := runTuningPush(nil, []string{}); err != nil {
		return errors.WithStack(err)
	}

	if err := runThisnodeStart(nil, []string{}); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func runThisnodeJoin(cmd *cobra.Command, args []string) error {
	if cubeSettings.IsRole(util.ROLE_CONTROL) {
		var ctrlIPs []string

		if len(args) == 1 {
			ctrlIPs = append(ctrlIPs, args[0])
		} else {
			ctrlIPs = cubeSettings.GetControlGroupIPs()
		}

		// The member certificate is shared and lists the control group it was signed for.
		// A control node added since then would join, and then be unreachable for its peers.
		if util.GetEtcdTLSMode() != util.EtcdTLSPlain {
			if err := util.EtcdMemberCertCovers(cubeSettings.GetMgmtIfIp(), cubeSettings.GetHostname()); err != nil {
				return errors.Wrap(err, "run `cubectl config cluster etcd-gencerts` on the master control node, "+
					"then commit the cluster on this node again")
			}
		}

		// Add to etcd cluster as learner
		// Add member to ETCD cluster and write config
		id, err := etcdMemberAdd(ctrlIPs, cubeSettings.GetHostname(), cubeSettings.GetMgmtIfIp())
		if err != nil {
			return errors.WithStack(err)
		}
		zap.S().Debugf("New ETCD member ID: " + strconv.FormatUint(id, 16))

		// Join etcd cluster
		if _, _, err := util.ExecCmd("systemctl", "start", "etcd"); err != nil {
			return errors.WithStack(err)
		}

		// Wait for the learner to be in sync with leader
		time.Sleep(1 * time.Second)

		// Promote to etcd member
		if err := etcdMemberPromote(ctrlIPs, id); err != nil {
			return errors.WithStack(err)
		}

		// if err := saveLocalMemberID(id); err != nil {
		// 	return errors.WithStack(err)
		// }
	}

	// Push node tuning to cluster after joining cluster
	if err := runTuningPush(nil, []string{}); err != nil {
		return errors.WithStack(err)
	}

	if err := runThisnodeStart(nil, []string{}); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func runThisnodeReset(cmd *cobra.Command, args []string) error {
	// if err := runTuningRemove(nil, []string{}); err != nil {
	// 	zap.S().Warn(err)
	// }

	// idStr, err := getLocalMemberID()
	// if err != nil {
	// 	zap.S().Warnf("Failed to get member ID - %v", err)
	// } else {

	// 	id, err := strconv.ParseUint(idStr, 16, 64)
	// 	if err != nil {
	// 		zap.S().Warn(err)
	// 	} else {

	// 		if err := etcdMemberRemove(cubeSettings.GetControllerIp(), id); err != nil {
	// 			zap.S().Warn(err)
	// 		}
	// 	}
	// }

	util.ExecCmd("systemctl", "stop", "etcd-watch")
	os.Remove(clusterTuningFile)
	os.Remove(revisionFile)

	if cubeSettings.IsRole(util.ROLE_CONTROL) {
		util.ExecCmd("systemctl", "stop", "etcd")
		os.RemoveAll(etcdDataDir)
		os.RemoveAll(etcdConfigDir)
	}

	return nil
}

var cmdThisnode = &cobra.Command{
	Use:   "this-node <subcommand>",
	Short: "Cubectl this-node",
}

var cmdThisnodeUp = &cobra.Command{
	Use:   "start",
	Short: "Start-up this node",
	Args:  cobra.NoArgs,
	RunE:  runThisnodeStart,
}

var cmdThisnodeNew = &cobra.Command{
	Use:   "new",
	Short: "Create a new cluster",
	Args:  cobra.NoArgs,
	RunE:  runThisnodeNew,
}

var cmdThisnodeJoin = &cobra.Command{
	Use:   "join <Controller IP>",
	Short: "Join this node to cluster",
	Args:  cobra.MaximumNArgs(1),
	RunE:  runThisnodeJoin,
}

var cmdThisnodeEtcdRefresh = &cobra.Command{
	Use:   "etcd-refresh",
	Short: "Bring local etcd in line with the node's etcd TLS mode, restarting it if needed",
	Args:  cobra.NoArgs,
	RunE:  runThisnodeEtcdRefresh,
}

var cmdThisnodeReset = &cobra.Command{
	Use:   "reset",
	Short: "reset this node for cluster",
	Args:  cobra.NoArgs,
	RunE:  runThisnodeReset,
}

func init() {
	RootCmd.AddCommand(cmdThisnode)
	cmdThisnode.AddCommand(cmdThisnodeUp)
	cmdThisnode.AddCommand(cmdThisnodeNew)
	cmdThisnode.AddCommand(cmdThisnodeJoin)
	cmdThisnode.AddCommand(cmdThisnodeReset)
	cmdThisnode.AddCommand(cmdThisnodeEtcdRefresh)
}
