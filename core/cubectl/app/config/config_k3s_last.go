package config

import (
	"context"
	"cubectl/util"
	"cubectl/util/ceph"
	"cubectl/util/docker"
	"cubectl/util/kube"
	cubeSettings "cubectl/util/settings"
	"cubectl/util/tgz"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"time"

	"github.com/coreos/go-systemd/v22/dbus"
	"github.com/pkg/errors"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
	corev1 "k8s.io/api/core/v1"
)

var (
	k3sTaintControlPlane = corev1.Taint{
		Key:    kube.TaintControlPlane,
		Value:  "true",
		Effect: corev1.TaintEffectNoSchedule,
	}
)

type k3sServiceConf struct {
	KubeLetArg []string `yaml:"kubelet-arg"`
}

type k3sResource struct {
	Kube   ReservedResource
	System ReservedResource
}

type ReservedResource struct {
	CPU              int64
	Memory           int64
	EphemeralStorage int64
}

func init() {
	m := NewModule("k3s_last")
	m.commitFunc = commitK3sLast
	m.resetFunc = resetLastK3s
}

func resetLastK3s() error {
	return nil
}

func isTaintControlPlane(taint corev1.Taint) bool {
	return taint.Key == kube.TaintControlPlane && taint.Effect == corev1.TaintEffectNoSchedule
}

func genK3sResourceConf(kube, system ReservedResource) k3sServiceConf {
	return k3sServiceConf{
		KubeLetArg: []string{
			fmt.Sprintf("kube-reserved=cpu=%d,memory=%dMi,ephemeral-storage=%dGi", kube.CPU, kube.Memory, kube.EphemeralStorage),
			fmt.Sprintf("system-reserved=cpu=%d,memory=%dMi", system.CPU, system.Memory),
			"eviction-hard=memory.available<15%,nodefs.available<10%",
		},
	}
}

func restartK3sService() error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	conn, err := dbus.NewWithContext(ctx)
	if err != nil {
		return errors.Wrapf(err, "Failed to create dbus connection")
	}
	defer conn.Close()

	ctx, cancel = context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	_, err = conn.RestartUnitContext(ctx, "k3s.service", "replace", nil)
	if err != nil {
		return errors.Wrapf(err, "Failed to restart unit")
	}

	return nil
}

func applyK3sConf(conf k3sServiceConf) error {
	file, err := os.Create(k3sServiceConfFile)
	if err != nil {
		return err
	}

	defer file.Close()
	body, err := yaml.Marshal(conf)
	if err != nil {
		return err
	}

	_, err = file.Write(body)
	if err != nil {
		return err
	}

	return nil
}

func isConfChanged(newConf k3sServiceConf) bool {
	_, err := os.Stat(k3sServiceConfFile)
	if err != nil {
		return true
	}

	body, err := os.ReadFile(k3sServiceConfFile)
	if err != nil {
		return false
	}

	oldConf := k3sServiceConf{}
	err = yaml.Unmarshal(body, &oldConf)
	if err != nil {
		return false
	}

	return !reflect.DeepEqual(
		newConf,
		oldConf,
	)
}

func genResourceReservedConf() (*k3sResource, error) {
	kubeReserved, err := getKubeReservedResources()
	if err != nil {
		return nil, err
	}

	systemReserved, err := getNovaReservedResources()
	if err != nil {
		return nil, err
	}

	return &k3sResource{
		Kube:   *kubeReserved,
		System: *systemReserved,
	}, nil
}

func syncSystemReservedResources() error {
	reservedConf, err := genResourceReservedConf()
	if err != nil {
		return err
	}

	k3sConf := genK3sResourceConf(reservedConf.Kube, reservedConf.System)
	if !isConfChanged(k3sConf) {
		return nil
	}

	err = applyK3sConf(k3sConf)
	if err != nil {
		return err
	}

	err = restartK3sService()
	if err != nil {
		return err
	}

	return nil
}

func alreadyHasTaintControlPlane(node *corev1.Node) bool {
	for _, taint := range node.Spec.Taints {
		if isTaintControlPlane(taint) {
			return true
		}
	}

	return false
}

func genPatchToDisableWorkerCapacity(node *corev1.Node) *corev1.Node {
	if alreadyHasTaintControlPlane(node) {
		return node
	}

	node.Spec.Taints = append(node.Spec.Taints, k3sTaintControlPlane)
	return node
}

func genPatchToEnableWorkerCapacity(node *corev1.Node) *corev1.Node {
	taints := []corev1.Taint{}
	for _, taint := range node.Spec.Taints {
		if isTaintControlPlane(taint) {
			continue
		}

		taints = append(taints, taint)
	}

	node.Spec.Taints = taints
	return node
}

func setPatchToOnOffWorkerCapacity(node *corev1.Node) (*corev1.Node, error) {
	if cubeSettings.IsRole(util.ROLE_COMPUTE) {
		return genPatchToEnableWorkerCapacity(node), nil
	}

	if cubeSettings.GetRole() == "moderator" {
		return genPatchToDisableWorkerCapacity(node), nil
	}

	return node, nil
}

func getNodeInfo() (*corev1.Node, error) {
	nodeName := cubeSettings.GetHostname()
	kubeCli.SetNodeClient()
	return kubeCli.GetNode(nodeName)
}

func syncWorkerAbility() error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	node, err := getNodeInfo()
	if err != nil {
		return err
	}

	patch, err := setPatchToOnOffWorkerCapacity(node)
	if err != nil {
		return err
	}

	_, err = kubeCli.UpdateNode(patch)
	if err != nil {
		return err
	}

	return nil
}

func setDefaultStorageClassTo(storageClass string) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	kubeCli.SetStorageClassClient()
	err = kubeCli.DisableCurrentDefaultStorageClasses()
	if err != nil {
		return errors.Wrapf(err, "Failed to disable current default storage class")
	}

	err = kubeCli.SetDefaultStorageClass(storageClass)
	if err != nil {
		return errors.Wrapf(err, "Failed to set default storage class")
	}

	return nil
}

func removeTmpUntarFiles(path string) {
	pattern := filepath.Join(path, "*.tar")
	tmpUntarFiles, err := filepath.Glob(pattern)
	if err != nil {
		zap.S().Errorf("failed to find tmp untar files: %s", err.Error())
		return
	}

	for _, file := range tmpUntarFiles {
		err := os.Remove(file)
		if err != nil {
			zap.S().Errorf("failed to remove tmp untar file(%s): %s", file, err.Error())
			return
		}
	}
}

func pushImagesToCuebRegistry(images []docker.Image) error {
	for _, image := range images {
		err := docker.PushImageToCubeRegistry(image)
		if err != nil {
			return errors.Wrapf(err, "Failed to push %s image to cube registry", image.Name)
		}
	}

	return nil
}

func untarLoalCephImageSet() error {
	tgzPath := fmt.Sprintf("%s/%s", ceph.CsiLocalStore, ceph.CsiImageSet)
	return tgz.Decompress(
		tgzPath,
		ceph.CsiLocalStore,
	)
}

func syncCephImagesToCubeRegistry() error {
	err := untarLoalCephImageSet()
	if err != nil {
		return err
	}

	defer removeTmpUntarFiles(ceph.CsiLocalStore)
	err = pushImagesToCuebRegistry(ceph.CsiImages)
	if err != nil {
		return err
	}

	return nil
}

func applyCephCsiDrivers() error {
	err := ceph.InitDefaultSubVolumeGroup()
	if err != nil {
		return errors.Wrapf(err, "Failed to init ceph default sub volume group")
	}

	err = syncCephImagesToCubeRegistry()
	if err != nil {
		return errors.Wrapf(err, "Failed to sync ceph csi images to local registry")
	}

	rbdChart, err := ceph.GenCsiRbdChart()
	if err != nil {
		return errors.Wrapf(err, "Failed to generate csi rbd chart")
	}

	fsChart, err := ceph.GenCsiFsChart()
	if err != nil {
		return errors.Wrapf(err, "Failed to generate csi fs chart")
	}

	nodeCount, err := k3sGetNodeCounts()
	if err != nil {
		return errors.Wrapf(err, "Failed to get node counts")
	}

	ceph.SyncProvisionerReplica(rbdChart, nodeCount)
	ceph.SyncProvisionerReplica(fsChart, nodeCount)
	err = ceph.ApplyCsiCharts(rbdChart, fsChart)
	if err != nil {
		return errors.Wrapf(err, "Failed to apply csi charts")
	}

	return nil
}

func isControlOrComputeNode() bool {
	if cubeSettings.GetRole() == "undef" {
		return false
	}

	return cubeSettings.IsRole(util.ROLE_CONTROL) ||
		cubeSettings.IsRole(util.ROLE_COMPUTE)
}

func commitK3sLast() error {
	if !isControlOrComputeNode() {
		return nil
	}

	err := applyCephCsiDrivers()
	if err != nil {
		return errors.WithStack(err)
	}

	err = setDefaultStorageClassTo(ceph.CsiRbdStorageClass)
	if err != nil {
		return errors.WithStack(err)
	}

	err = syncWorkerAbility()
	if err != nil {
		return errors.WithStack(err)
	}

	err = syncSystemReservedResources()
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}
