package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.etcd.io/etcd/clientv3"
	"go.etcd.io/etcd/mvcc/mvccpb"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	memberIDFile      = "/etc/etcd/member_id"
	clusterTuningFile = "/etc/settings.cluster.json"
	stagingDir        = "/etc/staging"
	stagingPolicyDir  = stagingDir + "/policies"
	revisionFile      = "/etc/revision"
)

func etcdGetLatestRevision() (int64, error) {
	cli, err := getEtcdClient(cubeSettings.GetControllerIp())
	if err != nil {
		return 0, err
	}
	defer cli.Close()

	ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
	resp, err := cli.Get(ctx, "\x00", clientv3.WithLastRev()...)
	cancel()
	if err != nil {
		return 0, err
	}

	return resp.Header.GetRevision(), nil
}

func getDeployedRevision() (int64, error) {
	data, err := ioutil.ReadFile(revisionFile)
	if err != nil {
		return 0, err
	}

	rev, err := strconv.ParseInt(string(data), 10, 64)
	if err != nil {
		return 0, err
	}

	return rev, nil
}

func saveRevison(rev int64, file string) error {
	revStr := strconv.FormatInt(rev, 10)

	_ = os.MkdirAll(path.Dir(file), 0755)

	return ioutil.WriteFile(file, []byte(revStr), 0644)
}

func runTuningPush(cmd *cobra.Command, args []string) error {
	info := util.Node{}
	info.Hostname = cubeSettings.GetHostname()
	info.Role = cubeSettings.GetRole()

	providerIf := cubeSettings.V().GetString("cubesys.provider")
	overlayIf := cubeSettings.V().GetString("cubesys.overlay")
	storageIf := cubeSettings.V().GetString("cubesys.storage")

	info.IP.Management = cubeSettings.GetMgmtIfIp()
	if providerIf != "" {
		info.IP.Provider = cubeSettings.V().GetString("net.if.addr." + providerIf)
	}
	if overlayIf != "" {
		info.IP.Overlay = cubeSettings.V().GetString("net.if.addr." + overlayIf)
	}
	if storageIf != "" {
		ifs := strings.Split(storageIf, ",")
		if len(ifs) == 1 {
			info.IP.Storage = cubeSettings.V().GetString("net.if.addr." + ifs[0])
		} else if len(ifs) == 2 {
			info.IP.Storage = cubeSettings.V().GetString("net.if.addr." + ifs[0])
			info.IP.StorageCluster = cubeSettings.V().GetString("net.if.addr." + ifs[1])
		}
	}

	// memberID, err := getLocalMemberID()
	// if err != nil {
	// 	return fmt.Errorf("Failed to get member ID: %v", err)
	// }
	// info.MemberID = memberID

	jsonBytes, _ := json.Marshal(info)
	jsonStr := string(jsonBytes)

	zap.S().Debugf("%s", jsonStr)

	etcdController := "localhost"
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		etcdController = cubeSettings.GetControllerIp()
	}

	cli, err := getEtcdClient(etcdController)
	if err != nil {
		return err
	}
	defer cli.Close()

	prefix := "cluster.node." + cubeSettings.GetHostname()
	var resp *clientv3.TxnResponse

	if err := util.Retry(
		func() error {
			ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
			resp, err = cli.Txn(ctx).
				If(
					clientv3.Compare(clientv3.Value(prefix), "=", jsonStr),
				).
				Else(
					clientv3.OpPut(prefix, jsonStr),
				).
				Commit()
			cancel()
			if err != nil {
				return err
			}

			return nil
		},
		5,
	); err != nil {
		return errors.Wrap(err, "Failed to push tuning")
	}

	zap.S().Infof("Successfully pushed cluster tuning, Revision: %d", resp.Header.GetRevision())

	return nil
}

func runTuningPull(cmd *cobra.Command, args []string) error {
	etcdController := "localhost"
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		etcdController = cubeSettings.GetControllerIp()
	}

	cli, err := getEtcdClient(etcdController)
	if err != nil {
		return err
	}
	defer cli.Close()

	var resp *clientv3.GetResponse
	prefix := "cluster.node"

	if err := util.Retry(
		func() error {
			ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
			resp, err = cli.Get(ctx, prefix, clientv3.WithPrefix())
			cancel()
			if err != nil {
				return err
			}

			return nil
		},
		5,
	); err != nil {
		return errors.Wrap(err, "Failed to pull cluster tuning")
	}

	nodes := util.NodeMap{}
	for _, ev := range resp.Kvs {
		key := string(ev.Key)
		idStr := key[strings.LastIndex(key, ".")+1:]
		//zap.S().Debug(key, idStr)
		zap.S().Debugf("Pulled cluster node: %s: %s", idStr, ev.Value)

		var nodeInfo util.Node
		if err := json.Unmarshal(ev.Value, &nodeInfo); err != nil {
			return err
		}
		nodes[idStr] = nodeInfo
	}

	jsonBytes, _ := json.Marshal(nodes)

	//fmt.Println(buf.String())
	err = ioutil.WriteFile(clusterTuningFile, jsonBytes, 0644)
	if err != nil {
		return fmt.Errorf("Failed to write cluster tuning file: %v", err)
	}

	prefixPolicy := "cluster._all_."

	if err := util.Retry(
		func() error {
			ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
			resp, err = cli.Get(ctx, prefixPolicy, clientv3.WithPrefix())
			cancel()
			if err != nil {
				return err
			}

			return nil
		},
		5,
	); err != nil {
		return errors.Wrap(err, "Failed to pull cluster policies")
	}

	zap.S().Debugf("Pulled cluster policies: %s", prefixPolicy)

	_ = os.MkdirAll(stagingPolicyDir, 0755)

	for _, ev := range resp.Kvs {
		key := string(ev.Key)
		policyPath := key[len(prefixPolicy):]

		var policyName string
		if idx := strings.Index(policyPath, "/"); idx <= 0 {
			return fmt.Errorf("Invalid policy: %s", policyPath)
		} else {
			policyName = policyPath[0:idx]
		}

		_ = os.MkdirAll(stagingPolicyDir+"/"+policyName, 0755)
		if err := ioutil.WriteFile(stagingPolicyDir+"/"+policyPath+".yaml", ev.Value, 0644); err != nil {
			return err
		}

		zap.S().Debugf("Wrote staging policie: %s", stagingPolicyDir+"/"+policyPath+".yaml")
	}

	// TODO: save revision file to staging directory
	rev := resp.Header.GetRevision()
	if err := saveRevison(rev, revisionFile); err != nil {
		return err
	}

	zap.S().Infof("Successfully pulled and write cluster tuning, Revision: %d", rev)

	return nil
}

func runTuningApply(cmd *cobra.Command, args []string) error {
	latestRev, err := etcdGetLatestRevision()
	if err != nil {
		return err
	}

	deployRev, err := getDeployedRevision()
	if err == nil && deployRev == latestRev {
		zap.S().Infof("Skipped. Already deployed latest revision: %d", deployRev)
	} else {
		if err := runTuningPull(nil, []string{}); err != nil {
			return err
		}

		// Run hex_confing apply even if staging policy dir is empty for cluster update
		if _, _, err := util.ExecCmd(hexConfigPath, "apply", stagingPolicyDir); err != nil {
			return err
		}

		// TODO
		// if rev, err := ioutil.ReadFile(stagingDir + "/revision"); err != nil {
		// 	return err
		// } else {
		// 	_ = ioutil.WriteFile(revisionFile, rev, 0644)
		// 	zap.S().Infof("Commited revision: %s", rev)
		// }
	}

	return nil
}

func runTuningRemove(cmd *cobra.Command, args []string) error {
	var host string
	if len(args) == 0 {
		host = cubeSettings.GetHostname()
	} else {
		host = args[0]
	}

	var ctrlIPs []string
	if cubeSettings.IsRole(util.ROLE_CONTROL) {
		ctrlIPs = []string{"localhost"}
		if cubeSettings.IsHA() {
			ctrlIPs = append(ctrlIPs, cubeSettings.GetControlGroupIPs()...)
		}
	} else {
		ctrlIPs = []string{cubeSettings.GetControllerIp()}
	}

	cli, err := getEtcdClient(ctrlIPs...)
	if err != nil {
		return err
	}
	defer cli.Close()

	prefix := "cluster.node." + host

	ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
	resp, err := cli.Delete(ctx, prefix, clientv3.WithPrefix())
	cancel()
	if err != nil {
		return fmt.Errorf("Failed to remove tuning: %v", err)
	}

	zap.S().Infof("Successfully removed cluster tuning, Revision: %d", resp.Header.GetRevision())
	return nil
}

func runTuningWatch(cmd *cobra.Command, args []string) error {
	cli, err := getEtcdClient(cubeSettings.GetControllerIp())
	if err != nil {
		return err
	}
	defer cli.Close()

	//action := fmt.Sprintf("cubectl tuning pull && hex_config merge %s cluster", clusterTuningFile)

	respchan := cli.Watch(clientv3.WithRequireLeader(context.Background()), "cluster.", clientv3.WithPrefix(), clientv3.WithPrevKV())
	for resp := range respchan {
		if resp.Canceled {
			zap.S().Errorf("Watch was canceled (%v)", resp.Err())
		}
		if resp.IsProgressNotify() {
			zap.S().Infof("Progress notify: %d", resp.Header.Revision)
		}

		//actionCmd := exec.Command("sh", "-c", action)
		zap.S().Infof("Cluster was changed, applying tuning")
		if err := runTuningApply(nil, []string{}); err != nil {
			zap.S().Error(err)
		}

		// Execute hex_config trigger for node add/remove events
		for _, ev := range resp.Events {
			typeStr := mvccpb.Event_EventType_name[int32(ev.Type)]
			keyByte := ev.Kv.Key
			valueByte := ev.Kv.Value
			preValByte := []byte{}
			if ev.PrevKv != nil {
				preValByte = ev.PrevKv.Value
			}

			zap.L().Debug("Watched Event",
				zap.String("type", string(typeStr)),
				zap.String("key", string(keyByte)),
				zap.String("value", string(valueByte)),
				zap.String("pre-value", string(preValByte)),
			)

			var act string
			var jsonByte []byte
			if typeStr == mvccpb.Event_EventType_name[0] {
				// "PUT"
				act = "add"
				jsonByte = valueByte
			} else if typeStr == mvccpb.Event_EventType_name[1] {
				// "DELETE"
				act = "remove"
				jsonByte = preValByte
			}

			var nodeInfo util.Node
			if err := json.Unmarshal(jsonByte, &nodeInfo); err != nil {
				zap.S().Error(err)
				continue
			}

			// Run hex_config trigger after hex_config apply becasue trigger is not protected by a lock
			if _, _, err := util.ExecCmd("hex_config", "trigger", "cluster_map_update", act, nodeInfo.Hostname, nodeInfo.IP.Management, nodeInfo.Role); err != nil {
				zap.S().Error(err)
				continue
			}

			zap.L().Info("Triggered cluster_map_update",
				zap.String("action", act),
				zap.String("hostname", nodeInfo.Hostname),
				zap.String("ip", nodeInfo.IP.Management),
				zap.String("role", nodeInfo.Role),
			)
		}
	}
	if err := cli.Close(); err != nil {
		return fmt.Errorf("Watch with error: %v", err)
	}

	return nil
}

var cmdTuning = &cobra.Command{
	Use:   "tuning <subcommand>",
	Short: "Control cluster tuning",
}

var cmdTuningPush = &cobra.Command{
	Use:   "push",
	Short: "Push cluster tunings to etcd",
	RunE:  runTuningPush,
}

var cmdTuningPull = &cobra.Command{
	Use:   "pull",
	Short: "Pull cluster tunings from etcd",
	RunE:  runTuningPull,
}

var cmdTuningApply = &cobra.Command{
	Use:   "apply",
	Short: "Pull and apply cluster tunings from etcd",
	RunE:  runTuningApply,
}

var cmdTuningRemove = &cobra.Command{
	Use:   "remove",
	Short: "Remove cluster tunings from etcd",
	Args:  cobra.MaximumNArgs(1),
	RunE:  runTuningRemove,
}

var cmdTuningWatch = &cobra.Command{
	Use:   "watch",
	Short: "Watch cluster tuning",
	Args:  cobra.NoArgs,
	RunE:  runTuningWatch,
}

func init() {
	RootCmd.AddCommand(cmdTuning)
	cmdTuning.AddCommand(cmdTuningPush)
	cmdTuning.AddCommand(cmdTuningPull)
	cmdTuning.AddCommand(cmdTuningApply)
	cmdTuning.AddCommand(cmdTuningRemove)
	cmdTuning.AddCommand(cmdTuningWatch)
}
