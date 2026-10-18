package config

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gophercloud/gophercloud"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	_ "github.com/go-sql-driver/mysql"
	kubeErr "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"cubectl/util"
	"cubectl/util/aws"
	"cubectl/util/ceph"
	"cubectl/util/kube"
	"cubectl/util/openstack"
	cubeSettings "cubectl/util/settings"
)

const (
	k3sDataDir                     = "/opt/k3s/"
	K3sBin                         = "k3s"
	K3sImage                       = "k3s-airgap-images-amd64.tar"
	k3sServiceFile                 = "/etc/systemd/system/k3s.service"
	k3sDbName                      = "k3s"
	k3sDbUser                      = "k3s"
	k3sDbPassword                  = "password"
	k3sBinPath                     = "/usr/local/bin/" + K3sBin
	k3sConfigFile                  = "/etc/rancher/k3s/k3s.yaml"
	k3sRegistriesFile              = "/etc/rancher/k3s/registries.yaml"
	k3sServiceConfFile             = "/etc/rancher/k3s/config.yaml"
	k3sCaCert                      = "/var/www/cert/server.cert"
	k3sKey                         = "/var/www/cert/server.key"
	k3sEtcdDir                     = "/var/lib/rancher/k3s/server/db/etcd/"
	k3sPort                        = 6443
	k3sIngressHttpPort             = 1080
	k3sIngressHttpsPort            = 10443
	k3sBucket                      = "k3s"
	k3sCubeManagedLabelKey         = "app.kubernetes.io/managed-by"
	k3sCubeManagedLabelValue       = "cube"
	k3sCubeMangedLabelKeyValuePair = k3sCubeManagedLabelKey + "=" + k3sCubeManagedLabelValue
	kubectlBinPath                 = "/usr/local/bin/kubectl"
	// Releases an in-place upgrade steps through, one per minor (core/k3s/Makefile)
	k3sLadderDir = k3sDataDir + "ladder/"
	// The k3s version this server last ran, written once it is Ready on it. Under
	// /var/lib/rancher/k3s, which CONFIG_MIGRATE carries to the new partition.
	k3sVersionFile = "/var/lib/rancher/k3s/cube-k3s-version"
	// What every release up to 3.2.0 shipped, and wrote no k3sVersionFile for
	k3sShippedVersion = "v1.26.6+k3s1"

	day = 24 * time.Hour
)

var (
	s3Cli       *aws.Helper
	kubeCli     *kube.Helper
	identityCli *gophercloud.ServiceClient

	defaultCubeManagedListOpts   = metav1.ListOptions{LabelSelector: k3sCubeMangedLabelKeyValuePair}
	defaultCubeManagedKeyPairMap = map[string]string{k3sCubeManagedLabelKey: k3sCubeManagedLabelValue}

	operation          string
	namespaces         []string
	noHeader           bool
	noQuota            bool
	noNamespace        bool
	nonSystemNamespace bool

	cmdK3sGetResourceOverview = &cobra.Command{
		Use:   "resource-overview-get",
		Short: "Get K3S resource overview",
		RunE: func(cmd *cobra.Command, args []string) error {
			return k3sGetResourceOverview()
		},
	}

	cmdK3sGetResourceAvailable = &cobra.Command{
		Use:   "available-resources-get",
		Short: "Get K3S available resources like CPU, memory, and ephemeral-storage",
		RunE: func(cmd *cobra.Command, args []string) error {
			return k3sGetAvailableResources()
		},
	}

	cmdK3sListNamespace = &cobra.Command{
		Use:   "namespace-list",
		Short: "List K3S namespaces with resource quota policy",
		RunE: func(cmd *cobra.Command, args []string) error {
			return k3sListNamespace(nonSystemNamespace)
		},
	}

	cmdK3sCreateNamespace = &cobra.Command{
		Use:   "namespace-create <namespace> --cpu <cpu quota> --memory <memory quota> --ephemeral-storage <ephemeral storage quota>",
		Short: "Create K3S namespace with resource quota policy",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			namespace := args[0]
			err := k3sCreateNamespaceWithResourceQuota(namespace)
			if err != nil {
				return err
			}

			fmt.Printf("Namespace %s created successfully \n", namespace)
			return nil
		},
	}

	cmdK3sUpdateNamespace = &cobra.Command{
		Use:   "namespace-update <namespace> --cpu <cpu quota> --memory <memory quota> --ephemeral-storage <ephemeral storage quota>",
		Short: "Update K3S namespace with resource quota policy",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			namespace := args[0]
			err := k3sUpdateNamespace(namespace)
			if err != nil {
				return err
			}

			fmt.Printf("Namespace %s updated successfully \n", namespace)
			return nil
		},
	}

	cmdK3sDeleteNamespace = &cobra.Command{
		Use:   "namespace-delete <namespace>",
		Short: "Delete K3S namespace",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			namespace := args[0]
			err := k3sDeleteNamespace(namespace)
			if err != nil {
				return err
			}

			fmt.Printf("Namespace %s deleted successfully \n", namespace)
			return nil
		},
	}

	cmdK3sListUser = &cobra.Command{
		Use:   "user-list",
		Short: "List K3S users with access namespaces",
		RunE: func(cmd *cobra.Command, args []string) error {
			return k3sListUsers()
		},
	}

	cmdK3sGetUser = &cobra.Command{
		Use:   "user-get",
		Short: "Get user details",
		RunE: func(cmd *cobra.Command, args []string) error {
			username := args[0]
			return k3sGetUser(username)
		},
	}

	cmdK3sCreateUser = &cobra.Command{
		Use:   "user-create <user> --namespaces <namespace1,namespace2,...>",
		Short: "Create a user with access to namespaces",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			username := args[0]
			return k3sCreateUser(username, namespaces)
		},
	}

	cmdK3sUpdateUser = &cobra.Command{
		Use:   "user-update <user> --operation <add|remove> --namespaces <namespace1,namespace2,...>",
		Short: "Update user with access to namespaces",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			username := args[0]
			err := k3sUpdateUser(username)
			if err != nil {
				return err
			}

			fmt.Printf("User %s updated successfully \n", username)
			return nil
		},
	}

	cmdK3sDeleteUser = &cobra.Command{
		Use:   "user-delete <user>",
		Short: "Delete user",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			username := args[0]
			err := k3sDeleteUser(username)
			if err != nil {
				return err
			}

			fmt.Printf("User %s deleted successfully \n", username)
			return nil
		},
	}

	cmdK3sExecAdmin = &cobra.Command{
		Use:   "admin-exec <cmd>",
		Short: "Execute k3s or helm command as admin",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return k3sExecAdminCmd(args[0])
		},
	}

	cmdK3sEnableAdminExec = &cobra.Command{
		Use:   "enable-admin-exec <yes or no>",
		Short: "Enable k3s admin direct control",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			operation := args[0]
			return k3sEnableAdminExec(operation)
		},
	}
)

func init() {
	m := NewModule("k3s")
	m.commitFunc = commitK3s
	m.resetFunc = resetK3s
	m.statusFunc = statusK3s
	m.checkFunc = checkK3s
	m.repairFunc = repairK3s

	// K3S resource oberservation
	m.AddCustomCommand(cmdK3sGetResourceOverview)
	m.AddCustomCommand(cmdK3sGetResourceAvailable)

	// K3S namespace management
	m.AddCustomCommand(cmdK3sListNamespace)
	cmdK3sListNamespace.Flags().BoolVarP(&nonSystemNamespace, "non-system-namespace", "", false, "Exclude/Include system namespaces")
	cmdK3sListNamespace.Flags().BoolVarP(&noHeader, "no-header", "", false, "Exclude header")
	cmdK3sListNamespace.Flags().BoolVarP(&noQuota, "no-quota", "", false, "Exclude resource quota")
	m.AddCustomCommand(cmdK3sCreateNamespace)
	cmdK3sCreateNamespace.Flags().StringVarP(&quotaCPU, "cpu", "c", defaultCpuQuota, "CPU quota")
	cmdK3sCreateNamespace.Flags().StringVarP(&quotaMemory, "memory", "m", defaultMemoryQuota, "Memory quota")
	cmdK3sCreateNamespace.Flags().StringVarP(&quotaEphemeralStorage, "ephemeral-storage", "o", defaultEphemeralStorageQuota, "Ephemeral storage quota")
	m.AddCustomCommand(cmdK3sUpdateNamespace)
	cmdK3sUpdateNamespace.Flags().StringVarP(&quotaCPU, "cpu", "c", defaultCpuQuota, "CPU quota")
	cmdK3sUpdateNamespace.Flags().StringVarP(&quotaMemory, "memory", "m", defaultMemoryQuota, "Memory quota")
	cmdK3sUpdateNamespace.Flags().StringVarP(&quotaEphemeralStorage, "ephemeral-storage", "o", defaultEphemeralStorageQuota, "Ephemeral storage quota")
	m.AddCustomCommand(cmdK3sDeleteNamespace)

	// K3S user management
	m.AddCustomCommand(cmdK3sGetUser)
	m.AddCustomCommand(cmdK3sCreateUser)
	cmdK3sCreateUser.Flags().StringSliceVarP(&namespaces, "namespaces", "n", []string{}, "Namespaces to access")
	m.AddCustomCommand(cmdK3sListUser)
	cmdK3sListUser.Flags().BoolVarP(&noHeader, "no-header", "", false, "Exclude header")
	cmdK3sListUser.Flags().BoolVarP(&noNamespace, "no-namespace", "", false, "Exclude namespace")
	m.AddCustomCommand(cmdK3sUpdateUser)
	cmdK3sUpdateUser.Flags().StringVarP(&operation, "operation", "o", "", "Operation to update user")
	cmdK3sUpdateUser.Flags().StringSliceVarP(&namespaces, "namespaces", "n", []string{}, "Namespaces to access")
	m.AddCustomCommand(cmdK3sDeleteUser)

	// K3S admin execution related operations
	m.AddCustomCommand(cmdK3sEnableAdminExec)
	m.AddCustomCommand(cmdK3sExecAdmin)
}

func initDependencyClients() error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	identityCli, err = openstack.NewIdentityCli()
	if err != nil {
		return err
	}

	err = syncStorageAccess()
	if err != nil {
		return err
	}

	s3Cli, err = aws.NewS3Client(
		aws.Region(aws.RegionAuto),
		aws.EnableStaticCreds(true),
		aws.AccessKey(aws.S3DefaultAccessKey),
		aws.SecretKey(aws.S3DefaultSecretKey),
		aws.EnableCustomURL(true),
		aws.S3Url(ceph.GetRadosGatewayUrl()),
		aws.InsecureSkipVerify(true),
	)
	if err != nil {
		return err
	}

	return nil
}

func getK3sMysqlDsn(host string) string {
	return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s", k3sDbUser, k3sDbPassword, host, mysqlPort, k3sDbName)
}

func createK3sDbIfNotExist(host string) error {
	if err := util.CheckService(host, mysqlPort, 10); err != nil {
		return errors.WithStack(err)
	}

	db, err := sql.Open("mysql", getK3sMysqlDsn(host))
	if err != nil {
		return errors.WithStack(err)
	}
	defer db.Close()

	if err := db.Ping(); err == nil {
		zap.L().Debug("K3s db existed")
	} else {
		db, err := sql.Open("mysql", "root@unix("+mysqlSockFile+")/")
		if err != nil {
			return errors.WithStack(err)
		}
		defer db.Close()

		_, err = db.Exec("CREATE DATABASE " + k3sDbName)
		if err != nil {
			return errors.WithStack(err)
		}

		_, err = db.Exec("GRANT ALL PRIVILEGES ON " + k3sDbName + ".* To '" + k3sDbUser + "'@'localhost' IDENTIFIED BY '" + k3sDbPassword + "'")
		if err != nil {
			return errors.WithStack(err)
		}

		_, err = db.Exec("GRANT ALL PRIVILEGES ON " + k3sDbName + ".* To '" + k3sDbUser + "'@'%' IDENTIFIED BY '" + k3sDbPassword + "'")
		if err != nil {
			return errors.WithStack(err)
		}

		zap.L().Info("K3s db created")
	}

	return nil
}

func k3sWriteRegistriesFile() error {
	const contentFmt = `
mirrors:
  docker.io:
    endpoint:
      - "http://localhost:%d"
  registry.k8s.io:
    endpoint:
      - "http://localhost:%d"
`

	os.MkdirAll(path.Dir(k3sRegistriesFile), 0755)
	if err := os.WriteFile(k3sRegistriesFile, []byte(fmt.Sprintf(contentFmt, dockerRegistryPort, dockerRegistryPort)), 0644); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func k3sGetNodeCounts() (int, error) {
	var count int

	out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", "nodes",
		"-o", `go-template={{len .items}}`,
	)
	if err != nil {
		return 0, errors.Wrap(err, outErr)
	}

	count, err = strconv.Atoi(out)
	if err != nil {
		return 0, errors.Wrap(err, outErr)
	}

	return count, nil
}

func k3sGetSpecReplicas(app string, namespace string) (int, error) {
	out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", app, "-n", namespace,
		"-o", `go-template={{.spec.replicas}}`,
	)
	if err != nil {
		return -1, errors.Wrap(err, outErr)
	}

	replicas, err := strconv.Atoi(out)
	if err != nil {
		return -1, errors.WithStack(err)
	}

	return replicas, nil
}

// Scale replicase according to number of control nodes
func k3sScaleAndWatchRollOut(namespace string, app string, scale bool) error {
	if scale {
		counts, err := k3sGetNodeCounts()
		if err != nil {
			return errors.WithStack(err)
		}

		if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
			"scale", fmt.Sprintf("--replicas=%d", counts),
			"-n", namespace, app,
		); err != nil {
			return errors.Wrap(err, outErr)
		}

		zap.L().Info("Application scaled", zap.String("namespace", namespace), zap.String("app", app), zap.Int("replicas", counts))
	}

	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"rollout", "status", "--timeout=5m",
		"-n", namespace, app,
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	zap.L().Info("Application rolled out", zap.String("namespace", namespace), zap.String("app", app))

	return nil
}

func k3sWatchRollOut(app string, namespace string, timeout string) error {
	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"rollout", "status", "--timeout", timeout,
		app, "-n", namespace,
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

func k3sGetReadyReplicas(app string, namespace string) (int, error) {
	var count int

	out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", app, "-n", namespace,
		"-o", `go-template={{.status.readyReplicas}}`,
	)
	if err != nil {
		return 0, errors.Wrap(err, outErr)
	}

	count, err = strconv.Atoi(out)
	if err != nil {
		return 0, errors.Wrap(err, outErr)
	}

	return count, nil
}

func k3sCheckReplicas(app string, namespace string) error {
	out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", app, "-n", namespace,
		"-o", `go-template={{.status.replicas}}`,
	)
	if err != nil {
		return errors.Wrap(err, outErr)
	}

	replicas, err := strconv.Atoi(out)
	if err != nil {
		return errors.WithStack(err)
	}

	nodeCount, err := k3sGetNodeCounts()
	if err != nil {
		return errors.WithStack(err)
	}

	if nodeCount != replicas {
		return fmt.Errorf("node count doesn't match replicas: %d != %d", nodeCount, replicas)
	}

	return nil
}

func k3sWaitResource(resource string, name string, namespace string, condition string, timeout string) error {
	_, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"wait", resource, name, "-n", namespace,
		"--for", "condition="+condition, "--timeout", timeout,
	)
	if err != nil {
		return errors.Wrap(err, outErr)
	}

	zap.L().Info("Resource condition met",
		zap.String("resource", resource),
		zap.String("name", name),
		zap.String("condition", condition),
	)

	return nil
}

func k3sWaitResourceReady(resource string, name string, namespace string, timeout string) error {
	_, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"wait", "--for=condition=Ready", "--timeout", timeout,
		resource, name, "-n", namespace,
	)
	if err != nil {
		return errors.Wrap(err, outErr)
	}

	zap.L().Info("Resource is ready", zap.String("resource", resource), zap.String("name", name))

	return nil
}

// kubectl wait fails at once with NotFound on an object that does not exist yet, and
// `systemctl restart k3s` returns before the kubelet has registered its node. On a slow
// host every wait can land in that gap: accept-3cc's cc1 registered 0.5s after the last
// attempt gave up, so the module never created the cube-controller service and keycloak
// could not resolve its database.
func k3sWaitNodeRegistered(name string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		_, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl", "get", "node", name)
		if err == nil {
			return nil
		}
		if time.Now().After(deadline) {
			return errors.Wrap(err, outErr)
		}
		time.Sleep(2 * time.Second)
	}
}

func k3sCreateControllerIpService(ip string) error {
	const contentFmt = `
kind: Service
apiVersion: v1
metadata:
 name: cube-controller
spec:
 clusterIP: None
---
kind: Endpoints
apiVersion: v1
metadata:
 name: cube-controller
subsets:
 - addresses:
     - ip: %s
`
	if _, outErr, err := util.ExecShf("echo '%s' | k3s kubectl apply -f -", fmt.Sprintf(contentFmt, ip)); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

func k3sConfigDns() error {
	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"rollout", "status", "--timeout=3m",
		"-n", "kube-system", "deployment.apps/coredns",
	); err != nil {
		return errors.Wrap(err, outErr)
	}
	zap.L().Debug("K3s CoreDNS rolled out")

	contentFmt := `
data:
  Corefile: |
    .:53 {
      errors
      health
      ready
      kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        upstream
        fallthrough in-addr.arpa ip6.arpa
      }
      hosts /etc/coredns/NodeHosts {
        reload 1s
        fallthrough
      }
      prometheus :9153
      forward . %s
      cache 30
      loop
      reload
      loadbalance
    }
`

	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"patch",
		"-n", "kube-system",
		"configmap", "coredns",
		"--patch", fmt.Sprintf(contentFmt, "8.8.8.8"),
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

// k3sIngressShouldUpgrade decides whether to (re)install the bundled ingress-nginx chart. A
// fresh install or --force always does. Otherwise a migration, or a deployed chart other than
// the bundled one, does -- but only once every k3s server runs the final release: the new
// chart may not run on the intermediate ones an upgrade passes through. Until then the
// deployed release stays, and k3s_upgrade_ladder's closing commit upgrades it.
func k3sIngressShouldUpgrade(nsExists, force, migration bool, deployedChart, shippedChart string, serversFinal bool) bool {
	if !nsExists || force {
		return true
	}
	if !migration && deployedChart == shippedChart {
		return false
	}
	return serversFinal
}

// The bundled chart as helm names it, e.g. ingress-nginx-4.15.1
func k3sIngressShippedChart() string {
	m, _ := filepath.Glob(k3sDataDir + "/ingress-nginx/ingress-nginx-*.tgz")
	if len(m) == 0 {
		return ""
	}
	return strings.TrimSuffix(filepath.Base(m[0]), ".tgz")
}

func k3sIngressDeployedChart() string {
	out, _, err := util.ExecCmd("helm", "--kubeconfig", k3sConfigFile, "list", "-n", "ingress-nginx", "-f", "^ingress-nginx$", "-o", "json")
	if err != nil {
		return ""
	}
	var rels []struct {
		Chart string `json:"chart"`
	}
	if json.Unmarshal([]byte(out), &rels) != nil || len(rels) == 0 {
		return ""
	}
	return rels[0].Chart
}

func k3sIngressDeploy() error {
	nsExists := k3sCheckNamespace("ingress-nginx")
	deployed, shipped := k3sIngressDeployedChart(), k3sIngressShippedChart()
	serversFinal := k3sServersAtFinal()
	upgrade := k3sIngressShouldUpgrade(nsExists, commitOpts.force, isMigration(), deployed, shipped, serversFinal)
	zap.L().Info("K3s ingress-nginx", zap.Bool("upgrade", upgrade), zap.String("deployed", deployed),
		zap.String("shipped", shipped), zap.Bool("serversFinal", serversFinal))
	if upgrade {
		// k3s has only just (re)started here, at boot or after the ladder, and
		// rancher-webhook (failurePolicy=Fail) is not serving yet, so the API server
		// answers 502. Give admission a few minutes before giving up on the chart.
		if err := util.Retry(func() error { return k3sCreateNamespace("ingress-nginx") }, 20); err != nil {
			return errors.WithStack(err)
		}

		if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
			"create", "secret",
			"-n", "ingress-nginx", "tls", "tls-private",
			"--cert="+certFile,
			"--key="+keyFile,
		); err != nil {
			zap.S().Warn(errors.Wrap(err, outErr))
		} else {
			zap.L().Info("K3s ingress secret created", zap.String("name", "tls-private"))
		}

		if err := util.Retry(
			func() error {
				if _, outErr, err := util.ExecShf("helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install ingress-nginx %s -n ingress-nginx --create-namespace -f %s",
					k3sDataDir+"/ingress-nginx/ingress-nginx-*.tgz", k3sDataDir+"/ingress-nginx/chart-values.yaml",
				); err != nil {
					return errors.Wrap(err, outErr)
				}
				zap.L().Info("K3s ingress-nginx release upgraded")

				return nil
			},
			2,
		); err != nil {
			return errors.WithStack(err)
		}
	}

	if err := k3sWatchRollOut("daemonset.apps/ingress-nginx-controller", "ingress-nginx", "3m"); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func k3sConfigTraefik() error {
	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"create", "secret",
		"tls", "kube-system   deployment.apps/traefik", "-n", "kube-system",
		"--cert="+certFile,
		"--key="+keyFile,
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	specFmt := `
spec:
  externalIPs:
  - %s
  ports:
  - name: http
    port: 1080
    protocol: TCP
    targetPort: http
  - name: https
    port: 10443
    protocol: TCP
    targetPort: https
`

	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"patch",
		"service/traefik", "-n", "kube-system",
		"--patch", fmt.Sprintf(specFmt, cubeSettings.GetControllerIp()),
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

func resetCephRbdAsDefaultStorageClassIfIsExist() error {
	sc, err := kubeCli.GetStorageClass(ceph.CsiRbdStorageClass)
	if err == nil {
		return setDefaultStorageClassTo(sc.Name)
	}

	if !kubeErr.IsNotFound(err) {
		return err
	}

	return nil
}

func disableCurrentDefaultStorageClasses() error {
	kubeCli.SetStorageClassClient()
	return kubeCli.DisableCurrentDefaultStorageClasses()
}

func syncDefaultStorageClass() error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	err = disableCurrentDefaultStorageClasses()
	if err != nil {
		return err
	}

	err = resetCephRbdAsDefaultStorageClassIfIsExist()
	if err != nil {
		return err
	}

	return nil
}

var k3sMinorRe = regexp.MustCompile(`^v1\.(\d+)\.`)

// k3sMinor returns 30 for v1.30.14+k3s2
func k3sMinor(v string) (int, bool) {
	m := k3sMinorRe.FindStringSubmatch(v)
	if m == nil {
		return 0, false
	}
	n, err := strconv.Atoi(m[1])
	return n, err == nil
}

// k3sPickBinary returns the k3s binary a server installs. Outside a migration it is the
// release this image runs. At a migration it is the next minor up from <recorded>, the version
// the server last ran, among the <ladder> releases, or the final release past the last of
// them: k3s upgrades one minor at a time, and k3s_upgrade_ladder (sdk_k3s.sh) takes the rest
// of the way. A record that does not parse counts as k3sShippedVersion.
func k3sPickBinary(migration bool, recorded string, ladder []string) string {
	final := k3sDataDir + K3sBin
	if !migration {
		return final
	}

	from, ok := k3sMinor(recorded)
	if !ok {
		from, _ = k3sMinor(k3sShippedVersion)
	}

	pick, pickMinor := final, 0
	for _, v := range ladder {
		if m, ok := k3sMinor(v); ok && m > from && (pickMinor == 0 || m < pickMinor) {
			pick, pickMinor = k3sLadderDir+v+"/"+K3sBin, m
		}
	}
	return pick
}

func k3sLadderVersions() []string {
	entries, _ := os.ReadDir(k3sLadderDir)
	vs := make([]string, 0, len(entries))
	for _, e := range entries {
		vs = append(vs, e.Name())
	}
	return vs
}

func k3sRecordedVersion() string {
	b, err := os.ReadFile(k3sVersionFile)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func k3sBinVersion(bin string) string {
	out, _, err := util.ExecCmd(bin, "--version")
	if err != nil {
		return ""
	}
	// k3s version v1.32.13+k3s1 (<commit>)
	if f := strings.Fields(out); len(f) >= 3 {
		return f[2]
	}
	return ""
}

func k3sRecordVersion() {
	v := k3sBinVersion(k3sBinPath)
	if v == "" {
		zap.S().Warn("K3s version unknown, not recorded")
		return
	}
	if err := os.WriteFile(k3sVersionFile, []byte(v+"\n"), 0644); err != nil {
		zap.S().Warn(errors.WithStack(err))
	}
}

// k3sServersAt reports whether every k3s server in <versions> runs <want>
func k3sServersAt(versions []string, want string) bool {
	if len(versions) == 0 {
		return false
	}
	for _, v := range versions {
		if v != want {
			return false
		}
	}
	return true
}

func k3sServersAtFinal() bool {
	out, _, err := util.ExecCmd(k3sBinPath, "kubectl", "get", "nodes",
		"-l", "node-role.kubernetes.io/control-plane",
		"-o", "jsonpath={.items[*].status.nodeInfo.kubeletVersion}",
	)
	if err != nil {
		return false
	}
	return k3sServersAt(strings.Fields(out), k3sBinVersion(k3sDataDir+K3sBin))
}

// True only when both the unit and the binary are present; a half-finished
// install (binary copied, install.sh failed) must still count as not installed.
func k3sIsInstalled() bool {
	if _, err := os.Stat(k3sServiceFile); err != nil {
		return false
	}
	if _, err := os.Stat(k3sBinPath); err != nil {
		return false
	}
	return true
}

func commitK3s() error {
	if cubeSettings.GetRole() == "undef" {
		return nil
	}

	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	// absence of the unit/binary is the signal: k3sEtcdDir is CONFIG_MIGRATE'd,
	// so it exists on an upgraded partition even without k3s installed
	_, err := os.Stat(k3sEtcdDir)
	etcdExists := err == nil
	migration := isMigration()
	if !etcdExists || commitOpts.force || migration || !k3sIsInstalled() {
		bin := k3sPickBinary(migration && etcdExists, k3sRecordedVersion(), k3sLadderVersions())
		zap.L().Info("K3s binary", zap.String("path", bin))
		util.ExecCmd("cp", "-f", bin, k3sBinPath)

		os.MkdirAll(path.Dir(k3sRegistriesFile), 0755)
		util.ExecCmd("cp", "-f", k3sDataDir+"/registries.yaml", k3sRegistriesFile)

		isRejoin := false
		if _, err := os.Stat(rejoinMarker); err == nil {
			isRejoin = true

			if _, outErr, err := util.ExecCmd("cubectl",
				"node", "exec", "--hosts=cube-controller",
				k3sDataDir+"/remove_node.sh", strings.ToLower(cubeSettings.GetHostname()),
			); err != nil {
				zap.S().Warn(err, outErr)
			}
		}

		// Joining servers reach the cluster through cube-controller (the VIP). k3s 1.28 and later
		// refuse to add a name to the server certificate just because a client asks for it
		// (--tls-san-security), so without these the first server's certificate does not cover
		// cube-controller and the others cannot join until something else adds it.
		envInstallK3sExec := "INSTALL_K3S_EXEC=--disable=traefik --disable=servicelb --tls-san=cube-controller "
		if ip := cubeSettings.GetControllerIp(); ip != "" {
			envInstallK3sExec += "--tls-san=" + ip + " "
		}
		envInstallK3sExec += os.Getenv("INSTALL_K3S_EXEC")

		if !isRejoin && cubeSettings.IsMasterControl() {
			envInstallK3sExec += " --cluster-init"
		} else {
			envInstallK3sExec += " --server https://cube-controller:6443"
		}

		if _, outErr, err := util.ExecCmdEnv([]string{
			"INSTALL_K3S_SKIP_DOWNLOAD=true",
			"INSTALL_K3S_SKIP_ENABLE=true",
			"INSTALL_K3S_SELINUX_WARN=true",
			"INSTALL_K3S_SKIP_SELINUX_RPM=true",
			"K3S_TOKEN=" + cubeSettings.V().GetString("cubesys.seed"),
			envInstallK3sExec,
		}, k3sDataDir+"/install.sh"); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("K3s installed")

		// Retries when multiple nodes joining concurrently
		// Restart and check if node is joined for control node rejoin
		if err := util.Retry(
			func() error {
				if _, _, err := util.ExecCmd("timeout", "60s", "systemctl", "restart", "k3s"); err != nil {
					return err
				}

				if err := k3sWaitNodeRegistered(strings.ToLower(cubeSettings.GetHostname()), 3*time.Minute); err != nil {
					return err
				}

				if err := k3sWaitResourceReady("node", strings.ToLower(cubeSettings.GetHostname()), "", "3m"); err != nil {
					return err
				}

				return nil
			},
			2,
		); err != nil {
			return errors.WithStack(err)
		}
		k3sRecordVersion()

		// Move self as k3s etcd leader to avoid leader lost at first control node during upgrade
		if cubeSettings.IsMasterControl() {
			if err := util.Retry(
				func() error {
					if _, _, err := util.ExecCmd("hex_sdk", "k3s_take_leader"); err != nil {
						return err
					}

					return nil
				},
				2,
			); err != nil {
				zap.S().Warn(errors.WithStack(err))
			}
		}

		if err := k3sScaleAndWatchRollOut("kube-system", "deployment.apps/coredns", true); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		if err := k3sCreateControllerIpService(cubeSettings.GetControllerIp()); err != nil {
			return errors.WithStack(err)
		}

		// The migration boot moved k3s one minor up. A single node has no other server to
		// wait for, so take the rest of the way now; the ingress below then sees the final
		// release. On HA the roll's end does it (power_roll_advance).
		if migration && !cubeSettings.IsHA() {
			if _, outErr, err := util.ExecCmd("hex_sdk", "k3s_upgrade_ladder", "nocommit"); err != nil {
				return errors.Wrap(err, outErr)
			}
		}
	}

	// k3s.service set TimeoutStartUSec=infinity by default
	// Avoid infinity waiting when HA master node is starting first by overriding the timeout
	if _, outErr, err := util.ExecCmd("timeout", "60s", "systemctl", "start", "k3s"); err != nil {
		return errors.Wrap(err, outErr)
	}

	err = syncDefaultStorageClass()
	if err != nil {
		return errors.WithStack(err)
	}

	if err := k3sIngressDeploy(); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func resetK3s() error {
	if resetOpts.hard {
		if _, _, err := util.ExecCmd("k3s-uninstall.sh"); err != nil {
			zap.S().Warn(err)
		}

		os.RemoveAll(k3sRegistriesFile)
	} else {
		if _, outErr, err := util.ExecCmd("cubectl",
			"node", "exec", "--hosts="+cubeSettings.GetControllerIp(),
			"k3s", "kubectl", "delete", "node", strings.ToLower(cubeSettings.GetHostname()), "--timeout=10s",
		); err != nil {
			zap.S().Warn(err, outErr)

			if _, outErr, err := util.ExecCmd("cubectl",
				"node", "exec", "--hosts="+cubeSettings.GetControllerIp(),
				fmt.Sprintf(`kubectl get node -o name %s | xargs -i kubectl patch {} -p '{"metadata":{"finalizers":[]}}' --type=merge`, strings.ToLower(cubeSettings.GetHostname())),
			); err != nil {
				zap.S().Warn(err, outErr)
			}
		}

		if _, _, err := util.ExecCmd("k3s-killall.sh"); err != nil {
			zap.S().Warn(err)
		}

		os.RemoveAll(k3sEtcdDir)
	}

	return nil
}

func statusK3s() error {
	if out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", "nodes",
		"-o", "wide",
	); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		fmt.Println(out)
	}

	return nil
}

func checkK3s() error {
	var cubeNodeCount int

	// Get cube cluster node count
	if out, outErr, err := util.ExecSh("cubectl node list --role=control | wc -l"); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		cubeNodeCount, err = strconv.Atoi(strings.TrimSuffix(out, "\n"))
		if err != nil {
			return errors.Wrap(err, outErr)
		}
	}

	// Get k3s cluster node count
	k3sNodeCount, err := k3sGetNodeCounts()
	if err != nil {
		return errors.WithStack(err)
	}

	zap.L().Debug("Node counts", zap.Int("k3s", k3sNodeCount), zap.Int("cube", cubeNodeCount))
	if cubeNodeCount != k3sNodeCount {
		return fmt.Errorf("k3s node count doesn't match cube node count: %d != %d", k3sNodeCount, cubeNodeCount)
	}

	// Check k3s node status
	if out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", "nodes",
		"-o", `go-template={{range .items}}{{range .status.conditions}}{{if eq .type "Ready"}}{{.status}}{{end}}{{end}}{{"\n"}}{{end}}`,
	); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		scanner := bufio.NewScanner(strings.NewReader(out))
		for scanner.Scan() {
			//zap.S().Debug(scanner.Text())
			if scanner.Text() != "True" {
				return fmt.Errorf("K3s node status not ready")
			}
		}
		if scanner.Err() != nil {
			return errors.WithStack(scanner.Err())
		}
	}

	return nil
}

func repairK3s() error {
	if _, outErr, err := util.ExecCmd("cubectl",
		"node", "exec", "--parallel", "--role=control",
		"systemctl", "restart", "k3s",
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}
