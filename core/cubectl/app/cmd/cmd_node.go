package cmd

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"path/filepath"
	"strings"
	"time"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"
	"golang.org/x/crypto/ssh"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

type ListOpts struct {
	json bool
	role string
}

type ExecOpts struct {
	hosts      []string
	role       string
	userPasswd string
	parallel   bool
	noHeader   bool
	timeout    uint
}

type AddOpts struct {
	passwd string
}

type RsyncOpts struct {
	hosts  []string
	role   string
	delete bool
}

var (
	listOpts  ListOpts
	execOpts  ExecOpts
	addOpts   AddOpts
	rsyncOpts RsyncOpts
)

func sshCmd(host, user, passwd, cmd string) ([]byte, error) {
	auth := []ssh.AuthMethod{ssh.Password(passwd)}
	// Add public key auth when passwd is empty
	if passwd == "" {
		key, err := ioutil.ReadFile("/root/.ssh/id_rsa")
		if err != nil {
			return nil, err
		}

		signer, err := ssh.ParsePrivateKey(key)
		if err != nil {
			return nil, err
		}

		auth = append(auth, ssh.PublicKeys(signer))
	}

	sshConfig := &ssh.ClientConfig{
		User:    user,
		Auth:    auth,
		Timeout: 5 * time.Second,
	}
	sshConfig.HostKeyCallback = ssh.InsecureIgnoreHostKey()

	client, err := ssh.Dial("tcp", host+":22", sshConfig)
	if err != nil {
		return nil, err
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		return nil, err
	}
	defer session.Close()

	return session.CombinedOutput(cmd)
}

func runNodeList(cmd *cobra.Command, args []string) error {
	nodeMap, err := util.LoadClusterSettings()
	zap.S().Debug("Nodes mapping", nodeMap)
	if err != nil {
		return nil
	}

	roleBits := util.ROLE_ALL
	if listOpts.role != "" {
		roleBits = util.RoleMap[listOpts.role].Role
	}

	outNodes := nodeMap.GetNodesByRole(roleBits)

	// List control nodes with the order in cubesys.control.hosts if control HA is enabled
	if cubeSettings.IsHA() && roleBits&util.ROLE_CONTROL > 0 {
		controlNodes := []util.Node{}
		otherNodes := []util.Node{}

		ctrlHosts := strings.Split(cubeSettings.V().GetString("cubesys.control.hosts"), ",")
		zap.S().Debug("Getting cubesys.control.hosts:", ctrlHosts)

		for _, host := range ctrlHosts {
			// Make host case insensitive since Viper uses case insensitive keys
			host = strings.ToLower(host)
			if _, ok := (*nodeMap)[host]; ok {
				controlNodes = append(controlNodes, (*nodeMap)[host])
			}
		}

		for _, node := range outNodes {
			if !util.RoleTest(node.Role, util.ROLE_CONTROL) {
				otherNodes = append(otherNodes, node)
			}
		}

		outNodes = append(controlNodes, otherNodes...)
	}

	if listOpts.json {
		nodesJSON, _ := json.Marshal(outNodes)
		fmt.Println(string(nodesJSON))
	} else {
		for _, n := range outNodes {
			fmt.Printf("%s,%s,%s\n", n.Hostname, n.IP.Management, n.Role)
		}
	}

	return nil
}

func runNodeExec(cmd *cobra.Command, args []string) error {
	var hosts []string
	nodeMap, err := util.LoadClusterSettings()

	if len(execOpts.hosts) > 0 {
		hosts = execOpts.hosts
	} else {
		if err != nil {
			return err
		}

		roleBits := util.ROLE_ALL
		if execOpts.role != "" {
			roleBits = util.RoleMap[execOpts.role].Role
		}

		for _, node := range nodeMap.GetNodesByRole(roleBits) {
			hosts = append(hosts, node.Hostname)
		}
	}

	userPasswd := strings.SplitN(execOpts.userPasswd, ":", 2)
	user := userPasswd[0]
	passwd := ""
	if len(userPasswd) == 2 {
		passwd = userPasswd[1]
	}

	if len(hosts) == 0 {
		return fmt.Errorf("no hosts to exec")
	}

	if execOpts.parallel {
		timeout := time.After(time.Duration(execOpts.timeout) * time.Second)
		type resultST struct {
			node    util.Node
			out     string
			elapsed time.Duration
		}
		resultChan := make(chan resultST, len(hosts))

		for _, host := range hosts {
			go func(h string) {
				var out string

				start := time.Now()
				outByte, err := sshCmd(h, user, passwd, strings.Join(args, " "))
				//if err != nil {
				//	out += err.Error() + "\n"
				//}
				out += string(outByte)

				elapsed := time.Since(start)
				resultChan <- resultST{(*nodeMap)[h], out, elapsed}
				zap.S().Debugf("Command executed on %s, err: %v", h, err)
			}(host)
		}

		for left := len(hosts); left > 0; {
			select {
			case res := <-resultChan:
				if !execOpts.noHeader {
					fmt.Println(strings.Repeat("#", 50))
					fmt.Printf("%s - %s - %s\n", res.node.Hostname, res.node.IP.Management, res.node.Role)
					fmt.Printf("Time elapsed: %.2f secs\n", res.elapsed.Seconds())
					fmt.Println(strings.Repeat("#", 50))
				}

				fmt.Print(res.out)
				left--
			case <-timeout:
				if execOpts.timeout == 0 {
					continue
				}

				return fmt.Errorf("timed out")
			}
		}
	} else {
		for _, host := range hosts {
			outByte, err := sshCmd(host, user, passwd, strings.Join(args, " "))
			zap.S().Debugf("Executing command on %s", host)
			fmt.Print(string(outByte))

			zap.S().Debugf("Executed command on %s, err: %v", host, err)
			if err != nil {
				return err
			}
		}
	}

	return nil
}

func runNodeAdd(cmd *cobra.Command, args []string) error {
	errCount := 0
	hosts := args
	for _, host := range hosts {
		// Should use password auth
		execOpts.hosts = []string{host}
		execOpts.userPasswd = "root:" + addOpts.passwd
		if err := runNodeExec(nil, []string{"cubectl", "this-node", "join", cubeSettings.GetMgmtIfIp()}); err != nil {
			errCount++
			zap.S().Errorf("failed to add node %s, reason: %v", host, err)
			continue
		}

		zap.S().Infof("Successfully added node %s", host)
	}

	if errCount > 0 {
		return fmt.Errorf("number of errors: %d", errCount)
	}

	return nil
}

func runNodeRemove(cmd *cobra.Command, args []string) error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return fmt.Errorf("can only be performed on control node")
	}

	hosts := args

	nodeMap, err := util.LoadClusterSettings()
	// Allow self remove for master rejoin case
	if err != nil && hosts[0] != cubeSettings.GetHostname() {
		return err
	}

	errCount := 0
	for _, host := range hosts {
		var node util.Node
		if host == cubeSettings.GetHostname() {
			node = util.Node{
				Hostname: cubeSettings.GetHostname(),
				Role:     cubeSettings.GetRole(),
			}
		} else {
			n, ok := (*nodeMap)[host]
			if !ok {
				zap.S().Error(err)
				continue
			}
			node = n
			zap.S().Debugf("Found node: %s in cluster", host)
		}
		zap.L().Debug("Node data", zap.Any("node", node))

		// Should use public key auth
		// execOpts.hosts = []string{node.IP.Management}
		hasErr := false
		// if err := runNodeExec(nil, []string{"cubectl", "this-node", "reset"}); err != nil {
		// 	hasErr = true
		// 	zap.S().Warnf("Failed to exec leave cluster command on node %s, reason: %v", host, err)

		if err := runTuningRemove(nil, []string{host}); err != nil {
			hasErr = true
			zap.S().Error(err)
		}

		ctrlIPs := []string{"localhost"}
		if cubeSettings.IsHA() {
			ctrlIPs = append(ctrlIPs, cubeSettings.GetControlGroupIPs()...)
		}

		if util.RoleTest(node.Role, util.ROLE_CONTROL) {
			if id, err := getEtcdMemberID(ctrlIPs, host); err != nil {
				hasErr = true
				zap.S().Error(err)
			} else {
				if err := etcdMemberRemove(ctrlIPs, id); err != nil {
					hasErr = true
					zap.S().Error(err)
				} else {
					zap.L().Info("Removed etcd member", zap.String("name", host), zap.Uint64("id", id))
				}
			}
		}
		// }

		if hasErr {
			errCount++
		} else {
			zap.S().Infof("Successfully removed node %s", host)
		}
	}

	if errCount > 0 {
		return fmt.Errorf("number of errors: %d", errCount)
	}

	return nil
}

func runNodeRsync(cmd *cobra.Command, args []string) error {
	//src := strings.TrimSuffix(args[0], "/")
	src := args[0]
	srcParts := strings.SplitN(src, ":", 2)

	var dsts []string
	if len(srcParts) == 1 {
		// rsync local files to remote nodes
		absPath, err := filepath.Abs(src)
		if err != nil {
			return errors.WithStack(err)
		}
		src = absPath

		var hosts []string
		if len(rsyncOpts.hosts) > 0 {
			hosts = rsyncOpts.hosts
		} else {
			nodeMap, err := util.LoadClusterSettings()
			if err != nil {
				return errors.WithStack(err)
			}

			roleBits := util.ROLE_ALL
			if rsyncOpts.role != "" {
				roleBits = util.RoleMap[rsyncOpts.role].Role
			}

			for _, node := range nodeMap.GetNodesByRole(roleBits) {
				// Exclude self node
				if node.IP.Management != cubeSettings.GetMgmtIfIp() {
					hosts = append(hosts, node.IP.Management)
				}
			}
		}

		for _, host := range hosts {
			dsts = append(dsts, host+":/")
		}
	} else {
		// rsync remote files to local node

		//dsts = append(dsts, path.Dir(srcParts[1]))
		dsts = append(dsts, "/")
	}

	for _, dst := range dsts {
		// task := grsync.NewTask(src, dst,
		// 	grsync.RsyncOptions{
		// 		Rsh:      "ssh -o StrictHostKeyChecking=no",
		// 		Relative: true,
		// 		Delete:   rsyncOpts.delete,
		// 	},
		// )

		// if err := task.Run(); err != nil {
		// 	return errors.WithStack(err)
		// }

		// zap.L().Debug("rsync done", zap.Any("log", task.Log()))

		rsyncArgs := []string{src, dst,
			"-e", "ssh -o StrictHostKeyChecking=no",
			"--archive",
			"--relative",
			"--keep-dirlinks",
		}
		if rsyncOpts.delete {
			rsyncArgs = append(rsyncArgs, "--delete")
		}

		zap.L().Debug("rsync in progress", zap.String("source", src), zap.String("destination", dst))

		if _, outErr, err := util.ExecCmd("rsync", rsyncArgs...); err != nil {
			return errors.Wrap(err, outErr)
		}

		zap.L().Info("rsync done", zap.String("source", src), zap.String("destination", dst))
	}

	return nil
}

var cmdNode = &cobra.Command{
	Use:   "node <subcommand>",
	Short: "Control cluster nodes",
}

var cmdNodeList = &cobra.Command{
	Use:   "list",
	Short: "List nodes",
	RunE:  runNodeList,
}

var cmdNodeExec = &cobra.Command{
	Use:   "exec",
	Short: "Exec command on node",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runNodeExec,
}

var cmdNodeAdd = &cobra.Command{
	Use:   "add <node>...",
	Short: "Add nodes to cluster",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runNodeAdd,
}

var cmdNodeRemove = &cobra.Command{
	Use:   "remove <node>...",
	Short: "Remove a node from cluster",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runNodeRemove,
}

var cmdNodeRsync = &cobra.Command{
	Use:   "rsync [host:]<src>",
	Short: "Sync files between nodes",
	Args:  cobra.ExactArgs(1),
	RunE:  runNodeRsync,
}

func init() {
	RootCmd.AddCommand(cmdNode)

	cmdNode.AddCommand(cmdNodeList)
	cmdNodeList.Flags().BoolVarP(&listOpts.json, "json", "j", false, "Output results as JSON")
	cmdNodeList.Flags().StringVarP(&listOpts.role, "role", "r", "", "Get nodes with specific role (control, network, compute, storage)")

	cmdNode.AddCommand(cmdNodeExec)
	cmdNodeExec.Flags().SetInterspersed(false)
	cmdNodeExec.Flags().StringSliceVarP(&execOpts.hosts, "hosts", "o", []string{}, "Specific hosts to execute (overwrites role)")
	cmdNodeExec.Flags().StringVarP(&execOpts.role, "role", "r", "", "Specific hosts with the role to execute (default: all roles)")
	cmdNodeExec.Flags().StringVarP(&execOpts.userPasswd, "user", "u", "root", "Specify username and password pair (username:password) for ssh authentication. Using public key auth if leaves password empty")
	cmdNodeExec.Flags().BoolVarP(&execOpts.parallel, "parallel", "p", false, "Execute command in parallel on each hosts")
	cmdNodeExec.Flags().BoolVarP(&execOpts.noHeader, "noheader", "n", false, "Do not display node infomation headers in parallel mode")
	cmdNodeExec.Flags().UintVarP(&execOpts.timeout, "timeout", "t", 0, "Execution timeout in parallel mode")

	cmdNode.AddCommand(cmdNodeAdd)
	cmdNodeAdd.Flags().StringVarP(&addOpts.passwd, "password", "p", "admin", "Specify root password for the node to be added")

	cmdNode.AddCommand(cmdNodeRemove)

	cmdNode.AddCommand(cmdNodeRsync)
	cmdNodeRsync.Flags().StringSliceVarP(&rsyncOpts.hosts, "hosts", "o", []string{}, "Specific hosts to execute (overwrites role)")
	cmdNodeRsync.Flags().StringVarP(&rsyncOpts.role, "role", "r", "", "Specific hosts with the role to execute (default: all roles)")
	cmdNodeRsync.Flags().BoolVar(&rsyncOpts.delete, "delete", false, "Delete extra files on destination directory")
}
