package ceph

import (
	"cubectl/util"
	"cubectl/util/helm"
	"cubectl/util/kube"
	"fmt"

	"github.com/pkg/errors"
	"helm.sh/helm/v3/pkg/cli/values"
)

func InitDefaultSubVolumeGroup() error {
       _, outErr, err := util.ExecCmd("timeout", "30", "ceph", "fs", "subvolumegroup", "create", "cephfs", DefaultFsSubVolumeGroup)
	if err != nil {
		return errors.Wrapf(err, "Failed to init default sub volume group(%s): %s", DefaultFsSubVolumeGroup, outErr)
	}

	return nil
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
