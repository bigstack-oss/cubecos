package ceph

import (
	"cubectl/util"
	"cubectl/util/helm"
	"cubectl/util/kube"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"

	"github.com/avast/retry-go"
	"github.com/pkg/errors"
	"helm.sh/helm/v3/pkg/cli/values"
)

// Bound each ceph call; --connect-timeout does not bound a hung mgr command.
const (
	cephConnectTimeout  = "10"
	cephCmdTimeout      = "20s"
	cephKillAfter       = "5s"
	cephReadyAttempts   = 30
	subVolGroupAttempts = 5
)

var errCephCmdTimeout = errors.New("ceph command timed out")

// cephCmd runs a ceph CLI call under a hard timeout.
func cephCmd(args ...string) (string, error) {
	full := append([]string{"-k", cephKillAfter, cephCmdTimeout, "ceph", "--connect-timeout", cephConnectTimeout}, args...)
	stdout, stderr, err := util.ExecCmd("timeout", full...)
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && (exitErr.ExitCode() == 124 || exitErr.ExitCode() == 137) {
			return stdout, errors.Wrapf(errCephCmdTimeout, "ceph %v", args)
		}
		return stdout, errors.Wrapf(err, "ceph %v: %s", args, stderr)
	}
	return stdout, nil
}

// subVolGroupExists reports whether the CSI subvolume group is already on cephfs.
func subVolGroupExists() (bool, error) {
	out, err := cephCmd("fs", "subvolumegroup", "ls", "cephfs", "--format", "json")
	if err != nil {
		return false, err
	}
	var groups []struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal([]byte(out), &groups); err != nil {
		return false, errors.Wrapf(err, "parse subvolumegroup ls: %q", out)
	}
	for _, g := range groups {
		if g.Name == DefaultFsSubVolumeGroup {
			return true, nil
		}
	}
	return false, nil
}

// InitDefaultSubVolumeGroup ensures the CSI cephfs subvolume group exists.
// A timed-out call (e.g. inactive PGs on cold boot) aborts without retrying.
func InitDefaultSubVolumeGroup() error {
	// Wait until a mon answers.
	if err := util.Retry(func() error {
		_, err := cephCmd("-s")
		return errors.Wrap(err, "ceph not reachable yet")
	}, cephReadyAttempts); err != nil {
		return errors.Wrap(err, "ceph did not become reachable for subvolumegroup create")
	}

	// Check then create; retry while the mgr volumes module comes up.
	return retry.Do(func() error {
		exists, err := subVolGroupExists()
		if err == nil && exists {
			return nil
		}
		if err == nil {
			_, err = cephCmd("fs", "subvolumegroup", "create", "cephfs", DefaultFsSubVolumeGroup)
		}
		if err != nil {
			err = errors.Wrapf(err, "Failed to init default sub volume group(%s)", DefaultFsSubVolumeGroup)
			if errors.Is(err, errCephCmdTimeout) {
				return retry.Unrecoverable(err)
			}
		}
		return err
	},
		retry.Attempts(subVolGroupAttempts),
		retry.Delay(1*time.Second),
		retry.MaxDelay(15*time.Second),
		retry.LastErrorOnly(true),
	)
}

func customizeCsiFsValues() (*values.Options, error) {
	clusterID, err := GetClusterID()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to get cluster ID")
	}

	tolerationControlPlane, err := GenTolerationControlPlane()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to generate toleration control plane")
	}

	csiConfig, err := GenCsiConfigString(CsiFs)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to generate csi rbd config")
	}

	secret, err := GenAdminSecretString()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to generate admin secret")
	}

	return &values.Options{
		Values: []string{
			"rbac.create=true",
			"nodeplugin.httpMetrics.enabled=false",
			fmt.Sprintf("nodeplugin.plugin.image.tag=%s", CsiRbdImageTag),
			"provisioner.provisioner.extraArgs[0]=feature-gates=Topology=false",
			"topology.enabled=false",
			"storageClass.create=true",
			"storageClass.name=ceph-fs",
			fmt.Sprintf("storageClass.clusterID=%s", clusterID),
			"storageClass.fsName=cephfs",
			"storageClass.pool=cephfs_data",
			"cephconf=[global]\n  auth_cluster_required = none\n  auth_service_required = none\n  auth_client_required = none\n  fuse_big_writes = true",
		},
		JSONValues: []string{
			fmt.Sprintf("provisioner.tolerations=%s", tolerationControlPlane),
			fmt.Sprintf("nodeplugin.tolerations=%s", tolerationControlPlane),
			fmt.Sprintf("csiConfig=%s", csiConfig),
			fmt.Sprintf("secret=%s", secret),
		},
	}, nil
}

func customizeCsiRbdValues() (*values.Options, error) {
	clusterID, err := GetClusterID()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to get cluster ID")
	}

	tolerationControlPlane, err := GenTolerationControlPlane()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to generate toleration control plane")
	}

	csiConfig, err := GenCsiConfigString(CsiRbd)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to generate csi rbd config")
	}

	secret, err := GenAdminSecretString()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to generate admin secret")
	}

	return &values.Options{
		Values: []string{
			"rbac.create=true",
			"nodeplugin.httpMetrics.enabled=false",
			fmt.Sprintf("nodeplugin.plugin.image.tag=%s", CsiRbdImageTag),
			"provisioner.provisioner.extraArgs[0]=feature-gates=Topology=false",
			"topology.enabled=false",
			"storageClass.create=true",
			"storageClass.name=ceph-rbd",
			fmt.Sprintf("storageClass.clusterID=%s", clusterID),
			"storageClass.pool=k8s-volumes",
			"cephconf=[global]\n  auth_cluster_required = none\n  auth_service_required = none\n  auth_client_required = none",
		},
		JSONValues: []string{
			fmt.Sprintf("provisioner.tolerations=%s", tolerationControlPlane),
			fmt.Sprintf("nodeplugin.tolerations=%s", tolerationControlPlane),
			fmt.Sprintf("csiConfig=%s", csiConfig),
			fmt.Sprintf("secret=%s", secret),
		},
	}, nil
}

func GenCsiFsChart() (*Chart, error) {
	customizedValues, err := customizeCsiFsValues()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to customize csi fs values")
	}

	return &Chart{
		Release:             CsiFsRelease,
		Namespace:           CsiFsNamespace,
		LocalTgz:            CsiFsLocalTgz,
		CustomizedValues:    customizedValues,
		ClusterRolesToPatch: FsClusterRolesToPatch,
	}, nil
}

func GenCsiRbdChart() (*Chart, error) {
	customizedValues, err := customizeCsiRbdValues()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to customize csi rbd values")
	}

	return &Chart{
		Release:             CsiRbdRelease,
		Namespace:           CsiRbdNamespace,
		LocalTgz:            CsiRbdLocalTgz,
		CustomizedValues:    customizedValues,
		ClusterRolesToPatch: RbdClusterRolesToPatch,
	}, nil
}

func patchClusterRoles(roles []string) error {
	k, err := kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return errors.Wrapf(err, "Failed to create kube client")
	}

	k.SetClusterRoleClient()
	for _, role := range roles {
		err = k.PatchClusterRole(role, AllowNodeFetchingPermission)
		if err != nil {
			return errors.Wrapf(err, "Failed to patch cluster role(%s)", role)
		}
	}

	return nil
}

func SyncProvisionerReplica(csiChart *Chart, nodeCount int) {
	csiChart.CustomizedValues.Values = append(
		csiChart.CustomizedValues.Values,
		fmt.Sprintf("provisioner.replicaCount=%d", nodeCount),
	)
}

func ApplyCsiCharts(charts ...*Chart) error {
	for _, c := range charts {
		h, err := helm.NewClient(
			helm.AuthType(kube.OutOfClusterAuth),
			helm.AuthFile(kube.K3sConfigFile),
			helm.CreateNamespace(true),
		)
		if err != nil {
			return errors.Wrapf(err, "Failed to new %s helm", c.Release)
		}

		err = h.LoadLocalChartTgz(c.LocalTgz)
		if err != nil {
			return errors.Wrapf(err, "Failed to load local %s chart", c.Release)
		}

		err = h.OverrideDefaultValues(*c.CustomizedValues)
		if err != nil {
			return errors.Wrapf(err, "Failed to override %s value", c.Release)
		}

		err = h.InitApplyOperator()
		if err != nil {
			return errors.Wrapf(err, "Failed to init %s applier", c.Release)
		}

		err = h.Apply(c.Release, c.Namespace)
		if err != nil {
			return errors.Wrapf(err, "Failed to apply %s chart", c.Release)
		}

		err = patchClusterRoles(c.ClusterRolesToPatch)
		if err != nil {
			return errors.Wrapf(err, "Failed to patch %s cluster roles", c.Release)
		}
	}

	return nil
}
