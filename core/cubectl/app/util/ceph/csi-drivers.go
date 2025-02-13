package ceph

import (
	"cubectl/util/docker"
	"fmt"

	"helm.sh/helm/v3/pkg/cli/values"
)

const (
	CsiLocalStore           = "/opt/k3s/ceph-csi"
	CsiImageSet             = "ceph-csi-images.tgz"
	CsiRbd                  = "rbd"
	CsiFs                   = "fs"
	DefaultFsSubVolumeGroup = "cephfs_default_sub_volume_group"

	CsiRbdRemoteTgz    = "https://ceph.github.io/csi-charts/rbd/ceph-csi-rbd-3.11.0.tgz"
	CsiRbdNamespace    = "ceph-csi-rbd"
	CsiRbdStorageClass = "ceph-rbd"
	CsiRbdRelease      = "ceph-csi-rbd"
	CsiRbdImageTag     = "v3.11.0"

	CsiFsRemoteTgz = "https://ceph.github.io/csi-charts/cephfs/ceph-csi-cephfs-3.11.0.tgz"
	CsiFsNamespace = "ceph-csi-cephfs"
	CsiFsRelease   = "ceph-csi-cephfs"
	CsiFsImageTag  = "v3.11.0"
)

var (
	CsiRbdLocalTgz = fmt.Sprintf("%s/ceph-csi-rbd-3.11.0.tgz", CsiLocalStore)
	CsiFsLocalTgz  = fmt.Sprintf("%s/ceph-csi-cephfs-3.11.0.tgz", CsiLocalStore)
	CsiImages      = []docker.Image{
		{
			Registry: "quay.io",
			Name:     "cephcsi/cephcsi",
			Tag:      "v3.11.0",
			LocalTar: fmt.Sprintf("%s/ceph-csi.tar", CsiLocalStore),
		},
		{
			Registry: "registry.k8s.io",
			Name:     "sig-storage/csi-snapshotter",
			Tag:      "v7.0.0",
			LocalTar: fmt.Sprintf("%s/ceph-csi-snapshotter.tar", CsiLocalStore),
		},
		{
			Registry: "registry.k8s.io",
			Name:     "sig-storage/csi-resizer",
			Tag:      "v1.10.0",
			LocalTar: fmt.Sprintf("%s/ceph-csi-resizer.tar", CsiLocalStore),
		},
		{
			Registry: "registry.k8s.io",
			Name:     "sig-storage/csi-provisioner",
			Tag:      "v4.0.0",
			LocalTar: fmt.Sprintf("%s/ceph-csi-provisioner.tar", CsiLocalStore),
		},
		{
			Registry: "registry.k8s.io",
			Name:     "sig-storage/csi-attacher",
			Tag:      "v4.5.0",
			LocalTar: fmt.Sprintf("%s/ceph-csi-attacher.tar", CsiLocalStore),
		},
		{
			Registry: "registry.k8s.io",
			Name:     "sig-storage/csi-node-driver-registrar",
			Tag:      "v2.10.0",
			LocalTar: fmt.Sprintf("%s/ceph-csi-node-driver-registrar.tar", CsiLocalStore),
		},
	}

	RbdClusterRolesToPatch      = []string{"ceph-csi-rbd-nodeplugin", "ceph-csi-rbd-provisioner"}
	FsClusterRolesToPatch       = []string{"ceph-csi-cephfs-nodeplugin", "ceph-csi-cephfs-provisioner"}
	AllowNodeFetchingPermission = []byte(`[
	    {
	        "op": "add",
	        "path": "/rules/-",
	        "value": {
	            "apiGroups": ["storage.k8s.io"],
	            "resources": ["csinodes"],
	            "verbs": ["get","list","watch"]
	        }
	    },
	    {
	        "op": "add",
	        "path": "/rules/-",
	        "value": {
	            "apiGroups": [""],
	            "resources": ["nodes"],
	            "verbs": ["get","list","watch"]
	        }
	    }
	]`)
)

type Chart struct {
	Release             string
	Namespace           string
	RemoteTgz           string
	LocalTgz            string
	CustomizedValues    *values.Options
	ClusterRolesToPatch []string
}

type CsiCluster struct {
	ClusterID string   `json:"clusterID"`
	Monitors  []string `json:"monitors"`
	CephFS    `json:"cephFS"`
}

type CephFS struct {
	SubVolumeGroup string `json:"subvolumeGroup"`
}

type Secret struct {
	Create   bool   `json:"create"`
	UserID   string `json:"userID"`
	UserKey  string `json:"userKey"`
	AdminID  string `json:"adminID"`
	AdminKey string `json:"adminKey"`
}
