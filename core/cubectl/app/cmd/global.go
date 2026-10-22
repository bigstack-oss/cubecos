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
	clientv3 "go.etcd.io/etcd/client/v3"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	etcdTimeout = 5 * time.Second
	etcdRetries = 10
	// etcd admits one learner at a time; a parallel joiner waits for it to be promoted
	etcdLearnerWait = 3 * time.Minute
	etcdConfigDir   = "/etc/etcd"
	etcdConfigFile  = etcdConfigDir + "/etcd.conf.yml"
	etcdDataDir     = "/var/lib/etcd.cube"
	etcdClientPort  = util.EtcdClientPort
	etcdPeerPort    = 12380
)

// etcdClientConfig dials https with the client certificate once the cluster enforces TLS,
// and plain http otherwise: in compat the members still serve http, and so do the nodes
// a rolling upgrade has not reached yet.
func etcdClientConfig(addrs ...string) (clientv3.Config, error) {
	if len(addrs) == 0 {
		addrs = []string{"localhost"}
	}

	mode := util.GetEtcdTLSMode()
	scheme := ""
	if mode == util.EtcdTLSEnforce {
		scheme = "https://"
	}

	var endpoints []string
	for _, addr := range addrs {
		endpoints = append(endpoints, scheme+addr+":"+strconv.Itoa(etcdClientPort))
	}

	cfg := clientv3.Config{
		Endpoints:   endpoints,
		DialTimeout: etcdTimeout,
		//DialOptions:          []grpc.DialOption{grpc.WithBlock()},
		//DialKeepAliveTime:    1 * time.Second,
		//DialKeepAliveTimeout: 1 * time.Second,
	}

	if mode == util.EtcdTLSEnforce {
		tlsCfg, err := util.EtcdClientTLSConfig()
		if err != nil {
			return cfg, fmt.Errorf("Failed to load etcd client certificate: %v", err)
		}
		cfg.TLS = tlsCfg
	}

	return cfg, nil
}

func getEtcdClient(addrs ...string) (*clientv3.Client, error) {
	cfg, err := etcdClientConfig(addrs...)
	if err != nil {
		return nil, err
	}

	cli, err := clientv3.New(cfg)
	if err != nil {
		return nil, fmt.Errorf("Failed to init etcd client: %v", err)
	}

	zap.L().Debug("Inited etcd client",
		zap.Strings("endpoints", cfg.Endpoints),
	)

	return cli, nil
}

// waitEtcdHealthy polls local etcd until it serves a request or the timeout elapses.
func waitEtcdHealthy(timeout time.Duration) error {
	cli, err := getEtcdClient("localhost")
	if err != nil {
		return err
	}
	defer cli.Close()

	deadline := time.Now().Add(timeout)
	for {
		ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
		_, err = cli.Get(ctx, "health")
		cancel()
		if err == nil {
			return nil
		}
		if time.Now().After(deadline) {
			return errors.Wrap(err, "etcd did not become healthy in time")
		}
		time.Sleep(1 * time.Second)
	}
}

func etcdMemberAdd(ctrlIPs []string, name string, myIp string) (uint64, error) {
	cli, err := getEtcdClient(ctrlIPs...)
	if err != nil {
		return 0, nil
	}
	defer cli.Close()

	peerUrls := []string{etcdPeerURL(util.GetEtcdTLSMode(), myIp)}
	var (
		resp *clientv3.MemberAddResponse
		//err  error
	)
	learnerDeadline := time.Now().Add(etcdLearnerWait)
	for i := 0; ; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), etcdTimeout)
		resp, err = cli.MemberAddAsLearner(ctx, peerUrls)
		cancel()
		if err != nil {
			if strings.Contains(err.Error(), "too many learner members") && time.Now().Before(learnerDeadline) {
				zap.L().Info("Another node is joining as learner; waiting for its promotion",
					zap.Error(err),
				)
				i--
				time.Sleep(1 * time.Second)
				continue
			}
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

// etcdPeerURL is where a member is reached by its peers. Only enforce moves it to https:
// the peer port cannot serve http and https at once, so in compat it stays on http.
func etcdPeerURL(mode util.EtcdTLSMode, ip string) string {
	scheme := "http"
	if mode == util.EtcdTLSEnforce {
		scheme = "https"
	}
	return fmt.Sprintf("%s://%s:%d", scheme, ip, etcdPeerPort)
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
	viper.SetConfigType("yaml")
	for k, v := range etcdConfigValues(util.GetEtcdTLSMode(), state, initCluster) {
		viper.Set(k, v)
	}

	_ = os.MkdirAll("/etc/etcd", 0755)
	return viper.WriteConfigAs(etcdConfigFile)
}

// etcdConfigValues is the whole etcd config for a node creating or joining the cluster.
func etcdConfigValues(mode util.EtcdTLSMode, state string, initCluster string) map[string]interface{} {
	conf := etcdModeConfig(mode)
	conf["name"] = cubeSettings.GetHostname()
	conf["data-dir"] = etcdDataDir
	conf["initial-cluster-token"] = cubeSettings.V().GetString("cubesys.seed")
	conf["initial-cluster-state"] = state
	if state == "existing" {
		conf["initial-cluster"] = initCluster
	}

	return conf
}

// etcdTransportKeys are what changes with the TLS mode. Nothing else in the config does,
// and none of them is part of the cluster membership.
var etcdTransportKeys = []string{
	"listen-client-urls",
	"advertise-client-urls",
	"listen-peer-urls",
	"initial-advertise-peer-urls",
	"client-transport-security",
	"peer-transport-security",
}

// etcdModeConfig sets every key in etcdTransportKeys that the mode uses.
//
// compat serves clients on http and https on the same port - etcd splits the two on one
// listener - but keeps the peer port on http: two peer listeners on one port fail to
// bind. Its peer TLS settings are there so that it can dial members that already
// enforce. Both advertised URLs stay http, so an http client asking for the member list
// (`etcdctl --cluster`) is not handed https endpoints it cannot use.
//
// enforce serves https only and checks certificates on both ports. The peer port also
// checks the CN: clients and members share one CA, and without allowed-cn the client
// certificate every node holds would open the peer port.
func etcdModeConfig(mode util.EtcdTLSMode) map[string]interface{} {
	myIp := cubeSettings.GetMgmtIfIp()

	clientScheme := "http"
	if mode == util.EtcdTLSEnforce {
		clientScheme = "https"
	}

	conf := map[string]interface{}{
		"listen-client-urls":          etcdListenClientUrls(mode),
		"advertise-client-urls":       fmt.Sprintf("%s://%s:%d", clientScheme, myIp, etcdClientPort),
		"listen-peer-urls":            etcdPeerURL(mode, myIp),
		"initial-advertise-peer-urls": etcdPeerURL(mode, myIp),
	}

	if mode == util.EtcdTLSPlain {
		return conf
	}

	tlsConf := func() map[string]interface{} {
		return map[string]interface{}{
			"cert-file":       util.EtcdMemberCertFile(),
			"key-file":        util.EtcdMemberKeyFile(),
			"trusted-ca-file": util.EtcdCACertFile(),
		}
	}
	clientTLS, peerTLS := tlsConf(), tlsConf()
	if mode == util.EtcdTLSEnforce {
		clientTLS["client-cert-auth"] = true
		peerTLS["client-cert-auth"] = true
		peerTLS["allowed-cn"] = []string{util.EtcdMemberCN}
	}
	conf["client-transport-security"] = clientTLS
	conf["peer-transport-security"] = peerTLS

	return conf
}

// etcdListenClientUrls is where etcd serves clients: loopback (cubectl, etcdctl-cube.sh,
// terraform), the management IP (member calls, `etcdctl --cluster`) and, in HA, the
// control VIP, which etcd-watch and every non-control node dial via GetControllerIp().
// A control that does not hold the VIP can still bind it: cubesys sets
// net.ipv4.ip_nonlocal_bind=1. Without a management IP it stays on the wildcard.
func etcdListenClientUrls(mode util.EtcdTLSMode) string {
	var schemes []string
	switch mode {
	case util.EtcdTLSCompat:
		schemes = []string{"http", "https"}
	case util.EtcdTLSEnforce:
		schemes = []string{"https"}
	default:
		schemes = []string{"http"}
	}

	addrs := []string{"0.0.0.0"}
	if myIp := cubeSettings.GetMgmtIfIp(); myIp != "" {
		addrs = []string{"127.0.0.1", myIp}
		if vip := cubeSettings.V().GetString("cubesys.control.vip"); cubeSettings.IsHA() && vip != "" && vip != myIp {
			addrs = append(addrs, vip)
		}
	}

	var urls []string
	for _, addr := range addrs {
		for _, scheme := range schemes {
			urls = append(urls, fmt.Sprintf("%s://%s:%d", scheme, addr, etcdClientPort))
		}
	}
	return strings.Join(urls, ",")
}

// refreshEtcdConfig brings an existing etcd config in line with the node's TLS mode and
// reports whether it changed anything. The file is written only when the node creates or
// joins the cluster, and upgrades carry it over as is, so a node would otherwise keep the
// listeners and transport it was installed with. Only etcdTransportKeys change; the
// membership keys are left alone. A file already in line is not rewritten.
func refreshEtcdConfig(file string) (bool, error) {
	b, err := ioutil.ReadFile(file)
	if err != nil {
		return false, err
	}

	conf := map[string]interface{}{}
	if err := yaml.Unmarshal(b, &conf); err != nil {
		return false, errors.Wrapf(err, "parse %s", file)
	}
	before, err := yaml.Marshal(conf)
	if err != nil {
		return false, errors.WithStack(err)
	}

	for _, k := range etcdTransportKeys {
		delete(conf, k)
	}
	for k, v := range etcdModeConfig(util.GetEtcdTLSMode()) {
		conf[k] = v
	}

	after, err := yaml.Marshal(conf)
	if err != nil {
		return false, errors.WithStack(err)
	}
	if bytes.Equal(before, after) {
		return false, nil
	}

	// write aside and rename, so a failed write cannot leave etcd without a config
	tmp := strings.TrimSuffix(file, ".yml") + ".new.yml"
	if err := ioutil.WriteFile(tmp, after, 0644); err != nil {
		return false, errors.WithStack(err)
	}
	return true, os.Rename(tmp, file)
}
