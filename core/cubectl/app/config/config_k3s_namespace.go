package config

import (
	"cubectl/util/kube"
	"fmt"
	"strconv"
	"strings"

	"github.com/dustin/go-humanize"
	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	kubeErr "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func k3sCreateNamespace(namespace string) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetNamespaceClient()
	err = kubeCli.CreateNamespace(metav1.ObjectMeta{Name: namespace})
	if err == nil {
		return nil
	}
	if !kubeErr.IsAlreadyExists(err) {
		return errors.WithStack(err)
	}

	return nil
}

func k3sCreateNamespaceWithResourceQuota(namespace string) error {
	requiredQuota, err := genRequiredQuota()
	if err != nil {
		return errors.WithStack(err)
	}

	err = checkIfQuotaIsEnough(requiredQuota)
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetNamespaceClient()
	err = kubeCli.CreateNamespace(metav1.ObjectMeta{
		Name:   namespace,
		Labels: defaultCubeManagedKeyPairMap,
	})
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetResourceQuotaClient(namespace)
	_, err = kubeCli.CreateResourceQuota(namespace, genKubeQuotaSpec(namespace))
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func k3sListNamespace(nonSystemNamespace bool) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	listOpts := metav1.ListOptions{}
	if nonSystemNamespace {
		listOpts = defaultCubeManagedListOpts
	}
	kubeCli.SetNamespaceClient()
	namespaces, err := kubeCli.ListNamespace(listOpts)
	if err != nil {
		return err
	}

	showFormattedNamespaces(namespaces)
	return nil
}

func k3sUpdateNamespace(namespace string) error {
	requiredQuota, err := genRequiredQuota()
	if err != nil {
		return errors.WithStack(err)
	}

	err = checkIfQuotaIsEnough(requiredQuota)
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	kubeCli.SetResourceQuotaClient(namespace)
	err = kubeCli.UpdateResourceQuota(
		namespace,
		genQuotaPatch(quotaCPU, quotaMemory, quotaEphemeralStorage),
	)
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func k3sDeleteNamespace(namespace string) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetNamespaceClient()
	err = kubeCli.DeleteNamespace(namespace)
	if err == nil {
		return nil
	}
	if kubeErr.IsNotFound(err) {
		return errors.WithStack(err)
	}

	forceRemove := []byte(`{"metadata":{"finalizers":[]}}`)
	err = kubeCli.PatchNamespace(namespace, forceRemove)
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func k3sCheckNamespace(namespace string) bool {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return false
	}

	kubeCli.SetNamespaceClient()
	_, err = kubeCli.GetNamespace(namespace)
	return err == nil
}

func k3sGetResourceOverview() error {
	quota, err := calculateResourceOverview()
	if err != nil {
		return err
	}

	capacityCpu := strconv.Itoa(int(quota.Capacity.CPU/1000)) + " Cores"
	allocatedCpu := strconv.Itoa(int(quota.Allocated.CPU/1000)) + " Cores"
	availableCpu := strconv.Itoa(int(quota.Available.CPU)) + " Cores"
	capacityMemory := humanize.Bytes(uint64(quota.Capacity.Memory))
	allocatedMemory := humanize.Bytes(uint64(quota.Allocated.Memory))
	availableMemory := humanize.Bytes(uint64(quota.Available.Memory))
	capacityEphemeralStorage := humanize.Bytes(uint64(quota.Capacity.EphemeralStorage))
	allocatedEphemeralStorage := humanize.Bytes(uint64(quota.Allocated.EphemeralStorage))
	availableEphemeralStorage := humanize.Bytes(uint64(quota.Available.EphemeralStorage))

	fmt.Printf("%-25s %-20s %-20s %-20s\n", "RESOURCE", "CAPACITY", "ALLOCATED", "AVAILABLE")
	fmt.Printf("%-25s %-20s %-20s %-20s\n", "CPU", capacityCpu, allocatedCpu, availableCpu)
	fmt.Printf("%-25s %-20s %-20s %-20s\n", "Memory", capacityMemory, allocatedMemory, availableMemory)
	fmt.Printf("%-25s %-20s %-20s %-20s\n", "Ephemeral-storage", capacityEphemeralStorage, allocatedEphemeralStorage, availableEphemeralStorage)

	return nil
}

func k3sGetAvailableResources() error {
	quota, err := calculateResourceOverview()
	if err != nil {
		return err
	}

	fmt.Printf(
		"Available resources: %s vCPUs; %s memory; %s ephemeral-storage\n",
		strconv.Itoa(int(quota.Available.CPU)),
		humanize.Bytes(uint64(quota.Available.Memory)),
		humanize.Bytes(uint64(quota.Available.EphemeralStorage)),
	)
	return nil
}

func checkAndAppendNamespace(serviceAccount corev1.ServiceAccount, namespace corev1.Namespace, roleBindings *rbacv1.RoleBindingList, namespaces *[]string) {
	for _, roleBinding := range roleBindings.Items {
		for _, subject := range roleBinding.Subjects {
			if !kube.IsBoundServiceAccount(subject, serviceAccount.Name, serviceAccount.Namespace) {
				continue
			}

			*namespaces = append(*namespaces, namespace.Name)
		}
	}
}

func aggregateAndShowFormattedUserNamespaceInfo(serviceAccount corev1.ServiceAccount, namespaces *corev1.NamespaceList) {
	accessNamespace := []string{}
	for _, namespace := range namespaces.Items {
		kubeCli.SetRoleBindingClient(namespace.Name)
		roleBindings, err := kubeCli.ListRoleBindings(defaultCubeManagedListOpts)
		if err != nil {
			continue
		}

		checkAndAppendNamespace(serviceAccount, namespace, roleBindings, &accessNamespace)
	}

	fmt.Printf(
		"%-20s %-20s\n",
		serviceAccount.Name,
		strings.Join(accessNamespace, ", "),
	)
}

func showNamespaceWithQuota(namespace corev1.Namespace) {
	kubeCli.SetResourceQuotaClient(namespace.Name)
	resourceQuotas, err := kubeCli.ListResourceQuota(metav1.ListOptions{})
	if err != nil {
		return
	}

	if len(resourceQuotas.Items) == 0 {
		fmt.Printf("%-15s %-80s %s\n", namespace.Name, "Null", namespace.Status.Phase)
		return
	}

	limits := getLimitMetrics(resourceQuotas)
	fmt.Printf("%-15s %-80s %s\n", namespace.Name, strings.Join(limits, ", "), namespace.Status.Phase)
}

func showFormattedNamespaces(namespaces *corev1.NamespaceList) {
	if len(namespaces.Items) == 0 {
		return
	}

	if !noHeader {
		fmt.Printf("%-15s %-80s %s\n", "NAMESPACE", "LIMIT", "STATUS")
	}

	for _, namespace := range namespaces.Items {
		if noQuota {
			fmt.Println(namespace.Name)
			continue
		}

		showNamespaceWithQuota(namespace)
	}
}

func getLimitMetrics(resourceQuotas *corev1.ResourceQuotaList) []string {
	limits := []string{}

	for _, resourceQuota := range resourceQuotas.Items {
		for resource, quantity := range resourceQuota.Status.Hard {
			limits = append(
				limits,
				fmt.Sprintf("%s: %s", resource, quantity.String()),
			)
		}
	}

	return limits
}
