package config

import (
	"cubectl/util"
	"cubectl/util/kube"
	"cubectl/util/openstack"
	cubeSettings "cubectl/util/settings"
	"fmt"

	"go.uber.org/zap"
	"gopkg.in/ini.v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var (
	defaultCpuQuota              = "500m"
	defaultMemoryQuota           = "256Mi"
	defaultEphemeralStorageQuota = "256Mi"

	quotaCPU              string
	quotaMemory           string
	quotaEphemeralStorage string

	isResrcAllowedToTune = map[string]bool{
		kube.Cpu:              true,
		kube.Memory:           true,
		kube.EphemeralStorage: true,
	}

	minimalK3sReservedResource = ReservedResource{
		CPU:              1,
		Memory:           512,
		EphemeralStorage: 50,
	}
)

type Quota struct {
	Capacity  Resource `yaml:"capacity"`
	Allocated Resource `yaml:"allocated"`
	Available Resource `yaml:"available"`
	Required  Resource `yaml:"required"`
}

type Resource struct {
	CPU              float64 `yaml:"cpu"`
	Memory           float64 `yaml:"memory"`
	EphemeralStorage float64 `yaml:"ephemeralStorage"`
}

func accumulateAllResource(quota *Quota, resrc corev1.ResourceName, quantity resource.Quantity) {
	switch resrc.String() {
	case kube.Cpu:
		quota.Capacity.CPU += float64(quantity.MilliValue())
	case kube.Memory:
		quota.Capacity.Memory += quantity.AsApproximateFloat64()
	case kube.EphemeralStorage:
		quota.Capacity.EphemeralStorage += quantity.AsApproximateFloat64()
	}
}

func accumulateAllocatedResource(quota *Quota, resrcQuota corev1.ResourceQuota) {
	for resrc, quantity := range resrcQuota.Status.Hard {
		switch resrc.String() {
		case kube.LimitCpu:
			quota.Allocated.CPU += float64(quantity.MilliValue())
		case kube.LimitMemory:
			quota.Allocated.Memory += quantity.AsApproximateFloat64()
		case kube.LimitEphemeralStorage:
			quota.Allocated.EphemeralStorage += quantity.AsApproximateFloat64()
		}
	}
}

func syncAvailableResources(quota *Quota) {
	quota.Available.CPU = (quota.Capacity.CPU - quota.Allocated.CPU) / 1000
	quota.Available.Memory = (quota.Capacity.Memory - quota.Allocated.Memory)
	quota.Available.EphemeralStorage = (quota.Capacity.EphemeralStorage - quota.Allocated.EphemeralStorage)
}

func syncAllocatedResources(quota *Quota, namespaces *corev1.NamespaceList) {
	for _, namespace := range namespaces.Items {
		kubeCli.SetResourceQuotaClient(namespace.Name)
		resrcQuotas, err := kubeCli.ListResourceQuota(metav1.ListOptions{})
		if err != nil {
			continue
		}

		for _, resrcQuota := range resrcQuotas.Items {
			accumulateAllocatedResource(quota, resrcQuota)
		}
	}
}

func getKubeReservedResources() (*ReservedResource, error) {
	if cubeSettings.IsRole(util.ROLE_COMPUTE) || cubeSettings.IsRole(util.ROLE_CONTROL) {
		return &minimalK3sReservedResource, nil
	}

	return nil, fmt.Errorf(
		"unknown role: %s to get kube reserved resources",
		cubeSettings.GetRole(),
	)
}

func genDefaultReservedResource() *ReservedResource {
	return &ReservedResource{
		CPU:              1,
		Memory:           1,
		EphemeralStorage: 80,
	}
}

func getNovaReservedResources() (*ReservedResource, error) {
	if cubeSettings.GetRole() == "moderator" {
		return genDefaultReservedResource(), nil
	}

	cfg, err := ini.Load(openstack.NovaConfFile)
	if err != nil {
		zap.S().Warnf("nova conf not found: %s. fallback to default reservation spec", err.Error())
		return genDefaultReservedResource(), nil
	}

	reservedCpu, err := cfg.Section("DEFAULT").Key(openstack.NovaReservedHostCpus).Int64()
	if err != nil {
		zap.S().Warnf("nova reserved cpu not found. fallback to default cpu spec(1 core)")
		reservedCpu = 1
	}

	reservedMemory, err := cfg.Section("DEFAULT").Key(openstack.NovaReservedHostMemoryMiB).Int64()
	if err != nil {
		zap.S().Warnf("nova reserved mem not found. fallback to default mem spec(1Gi)")
		reservedMemory = 1000
	}

	return &ReservedResource{
		CPU:    reservedCpu,
		Memory: reservedMemory,
	}, nil
}

func isNodeCannotAllocatePod(node corev1.Node) bool {
	for _, taint := range node.Spec.Taints {
		if isTaintControlPlane(taint) {
			return true
		}
	}

	return false
}

func syncNodeQuota(quota *Quota, node corev1.Node) {
	for resrc, quantity := range node.Status.Allocatable {
		if !isResrcAllowedToTune[resrc.String()] {
			continue
		}

		accumulateAllResource(quota, resrc, quantity)
	}
}

func syncOverallResources(quota *Quota, nodes *corev1.NodeList) {
	for _, node := range nodes.Items {
		if isNodeCannotAllocatePod(node) {
			continue
		}

		syncNodeQuota(quota, node)
	}
}

func calculateResourceOverview() (*Quota, error) {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return nil, err
	}

	kubeCli.SetNodeClient()
	nodes, err := kubeCli.ListNodes()
	if err != nil {
		return nil, err
	}

	kubeCli.SetNamespaceClient()
	namespaces, err := kubeCli.ListNamespace(defaultCubeManagedListOpts)
	if err != nil {
		return nil, err
	}

	quota := Quota{}
	syncOverallResources(&quota, nodes)
	syncAllocatedResources(&quota, namespaces)
	syncAvailableResources(&quota)

	return &quota, nil
}

func genKubeQuotaSpec(name string) *corev1.ResourceQuota {
	return &corev1.ResourceQuota{
		ObjectMeta: metav1.ObjectMeta{
			Name:   name,
			Labels: defaultCubeManagedKeyPairMap,
		},
		Spec: corev1.ResourceQuotaSpec{
			Hard: corev1.ResourceList{
				corev1.ResourceLimitsCPU:              resource.MustParse(quotaCPU),
				corev1.ResourceLimitsMemory:           resource.MustParse(quotaMemory),
				corev1.ResourceLimitsEphemeralStorage: resource.MustParse(quotaEphemeralStorage),
			},
		},
	}
}

func genQuotaPatch(cpu, memory, ephemeralStorage string) []byte {
	return []byte(`{
		"spec":{
			"hard":{
				"limits.cpu":"` + cpu + `",
				"limits.memory":"` + memory + `",
				"limits.ephemeral-storage":"` + ephemeralStorage + `"
			}
		}
	}`)
}

func genRequiredQuota() (*Quota, error) {
	cpu, err := resource.ParseQuantity(quotaCPU)
	if err != nil {
		return nil, err
	}

	memory, err := resource.ParseQuantity(quotaMemory)
	if err != nil {
		return nil, err
	}

	storage, err := resource.ParseQuantity(quotaEphemeralStorage)
	if err != nil {
		return nil, err
	}

	return &Quota{
		Required: Resource{
			CPU:              float64(cpu.MilliValue()) / 1000,
			Memory:           memory.AsApproximateFloat64(),
			EphemeralStorage: storage.AsApproximateFloat64(),
		},
	}, nil
}

func checkIfQuotaIsEnough(requiredQuota *Quota) error {
	currentQuota, err := calculateResourceOverview()
	if err != nil {
		return err
	}

	if requiredQuota.Required.CPU >= currentQuota.Available.CPU {
		return kube.ErrCpuQuotaExceeded
	}

	if requiredQuota.Required.Memory >= currentQuota.Available.Memory {
		return kube.ErrMemoryQuotaExceeded
	}

	if requiredQuota.Required.EphemeralStorage >= currentQuota.Available.EphemeralStorage {
		return kube.ErrEphemeralStorageStorageQuotaExceeded
	}

	return nil
}
