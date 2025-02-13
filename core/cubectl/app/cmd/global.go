package cmd

import (
	"bytes"
	"context"
	"fmt"
	"io/ioutil"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/errors"
	"github.com/spf13/viper"
	"go.etcd.io/etcd/clientv3"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	etcdTimeout    = 5 * time.Second
	etcdRetries    = 10
	etcdConfigDir  = "/etc/etcd"
	etcdConfigFile = etcdConfigDir + "/etcd.conf.yml"
	etcdDataDir    = "/var/lib/etcd.cube"
	etcdClientPort = 12379
	etcdPeerPort   = 12380
)

func getEtcdClient(addrs ...string) (*clientv3.Client, error) {
	if len(addrs) == 0 {
		addrs = []string{"localhost"}
	}

	var endpoints []string
	for _, addr := range addrs {
		endpoints = append(endpoints, addr+":"+strconv.Itoa(etcdClientPort))
	}

	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   endpoints,
		DialTimeout: etcdTimeout,
		//DialOptions:          []grpc.DialOption{grpc.WithBlock()},
		//DialKeepAliveTime:    1 * time.Second,
		//DialKeepAliveTimeout: 1 * time.Second,
	})
	if err != nil {
		return nil, fmt.Errorf("Failed to init etcd client: %v", err)
	}

	zap.L().Debug("Inited etcd client",
		zap.Strings("endpoints", endpoints),
	)

	return cli, nil
}

func etcdMemberAdd(ctrlIPs []string, name string, myIp string) (uint64, error) {
	cli, err := getEtcdClient(ctrlIPs...)
	if err != nil {
		return 0, nil
	}
	defer cli.Close()

	peerUrls := []string{"http://" + myIp + ":" + strconv.Itoa(etcdPeerPort)}
	var (
		resp *clientv3.MemberAddResponse
		//err  error
	)
	for i := 0; ; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
		resp, err = cli.MemberAddAsLearner(ctx, peerUrls)
		cancel()
		if err != nil {
			if i < etcdRetries {
				zap.L().Warn("Failed to add member",
					zap.Error(err),
					zap.Int("retries", i),
				)
				time.Sleep(1 * time.Second)
				continue
			}
			return 0, err
		} else {
			break
		}
	}

	myID := resp.Member.ID
	nameUrls := []string{}
	for _, member := range resp.Members {
		for _, url := range member.PeerURLs {
			n := member.Name
			if member.ID == myID {
				n = name
			}
			nameUrls = append(nameUrls, fmt.Sprintf("%s=%s", n, url))
		}
	}

	if err := writeEtcdConfig("existing", strings.Join(nameUrls, ",")); err != nil {
		return myID, err
	}

	return myID, nil
}

func etcdMemberRemove(ctrlIPs []string, id uint64) error {
	cli, err := getEtcdClient(ctrlIPs...)
	if err != nil {
		return err
	}
	defer cli.Close()

	zap.S().Debugf("Removing ETCD member: %d", id)

	for i := 0; ; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
		_, err := cli.MemberRemove(ctx, id)
		cancel()
		if err != nil {
			if err.Error() == "etcdserver: unhealthy cluster" && i < etcdRetries {
				zap.L().Warn("Failed to remove member",
					zap.Error(err),
					zap.Int("retries", i),
				)
				time.Sleep(1 * time.Second)
				continue
			}
			return err
		} else {
			break
		}
	}

	return nil
}

func etcdMemberPromote(ctrlIPs []string, id uint64) error {
	cli, err := getEtcdClient(ctrlIPs...)
	if err != nil {
		return nil
	}
	defer cli.Close()

	for i := 0; ; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
		_, err := cli.MemberPromote(ctx, id)
		cancel()
		if err != nil {
			if i < etcdRetries {
				zap.L().Warn("Failed to promote member",
					zap.Error(err),
					zap.Int("retries", i),
				)
				time.Sleep(1 * time.Second)
				continue
			}
			return err
		} else {
			break
		}
	}

	return nil
}

// func getSelfEtcdMemberID(ctrlIp string, name string) (uint64, error) {
// 	//id := uint64(0)
// 	cli, err := getEtcdClient(ctrlIp)
// 	if err != nil {
// 		return 0, nil
// 	}
// 	defer cli.Close()

// 	ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
// 	resp, err := cli.MemberList(ctx)
// 	cancel()
// 	if err != nil {
// 		return 0, nil
// 	}

// 	for _, member := range resp.Members {
// 		if member.Name == name {
// 			return member.ID, nil
// 		}
// 	}

// 	return 0, fmt.Errorf("Member is not found in clsuter: %s", name)
// }

func getEtcdMemberID(ctrlIPs []string, name string) (uint64, error) {
	//id := uint64(0)
	cli, err := getEtcdClient(ctrlIPs...)
	if err != nil {
		return 0, nil
	}
	defer cli.Close()

	ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
	resp, err := cli.MemberList(ctx)
	cancel()
	if err != nil {
		return 0, nil
	}

	for _, member := range resp.Members {
		if member.Name == name {
			return member.ID, nil
		}
	}

	return 0, fmt.Errorf("Member is not found in clsuter: %s", name)
}

func etcdStart() error {
	_, _, err := util.ExecCmd("systemctl", "start", "etcd", "etcd-watch")
	return err
}

func etcdStop() error {
	_, _, err := util.ExecCmd("systemctl", "stop", "etcd-watch", "etcd")
	return err
}

func saveLocalMemberID(id uint64) error {
	b := []byte(strconv.FormatUint(id, 16))
	return ioutil.WriteFile(memberIDFile, b, 0644)
}

func getLocalMemberID() (string, error) {
	id, err := ioutil.ReadFile(memberIDFile)
	if err != nil {
		//zap.S().Infof("Failed to get member id file: %v\n", err)
		return "", err
	}

	strID := string(bytes.Trim(id, "\n"))
	if len(strID) == 0 {
		err = errors.New("invalid member ID")
	}

	return strID, err
}

func writeEtcdConfig(state string, initCluster string) error {
	myIp := cubeSettings.GetMgmtIfIp()

	viper.SetConfigType("yaml")
	viper.Set("name", cubeSettings.GetHostname())
	viper.Set("data-dir", etcdDataDir)
	viper.Set("listen-client-urls", fmt.Sprintf("http://0.0.0.0:%d", etcdClientPort))
	viper.Set("listen-peer-urls", fmt.Sprintf("http://%s:%d", myIp, etcdPeerPort))
	viper.Set("advertise-client-urls", fmt.Sprintf("http://%s:%d", myIp, etcdClientPort))
	viper.Set("initial-advertise-peer-urls", fmt.Sprintf("http://%s:%d", myIp, etcdPeerPort))
	viper.Set("initial-cluster-token", cubeSettings.V().GetString("cubesys.seed"))
	viper.Set("initial-cluster-state", state)
	if state == "existing" {
		viper.Set("initial-cluster", initCluster)
	}

	_ = os.MkdirAll("/etc/etcd", 0755)
	return viper.WriteConfigAs(etcdConfigFile)
}
