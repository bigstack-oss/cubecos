package kube

import (
	"context"
	"fmt"
	"time"

	"github.com/pkg/errors"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	storagev1 "k8s.io/api/storage/v1"
	confCorev1 "k8s.io/client-go/applyconfigurations/core/v1"
	confRbacv1 "k8s.io/client-go/applyconfigurations/rbac/v1"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	_ "k8s.io/client-go/plugin/pkg/client/auth/oidc"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/leaderelection"
	"k8s.io/client-go/tools/leaderelection/resourcelock"
)

const (
	K3sConfigFile = "/etc/rancher/k3s/k3s.yaml"

	Cpu              = "cpu"
	Memory           = "memory"
	EphemeralStorage = "ephemeral-storage"

	LimitCpu              = "limits.cpu"
	LimitMemory           = "limits.memory"
	LimitEphemeralStorage = "limits.ephemeral-storage"
)

var (
	DefaultCluster   = "cluster"
	DefaultNamespace = "default"
	DefaultUser      = "default"

	InClusterAuth    = "inCluster"
	OutOfClusterAuth = "outOfCluster"
	LeaseRun         = leaderelection.RunOrDie

	RbacAuthGroup      = "rbac.authorization.k8s.io"
	KindServiceAccount = "ServiceAccount"

	ClusterRole         = "ClusterRole"
	ClusterRoleCubeUser = "cube-user"

	RoleRefAdminNamespace = &rbacv1.RoleRef{
		Kind:     "ClusterRole",
		Name:     "admin",
		APIGroup: rbacv1.GroupName,
	}
	RoleRefCubeUser = rbacv1.RoleRef{
		Kind:     ClusterRole,
		Name:     ClusterRoleCubeUser,
		APIGroup: RbacAuthGroup,
	}

	CubeUser = []rbacv1.PolicyRule{
		{
			APIGroups: []string{""},
			Resources: []string{"namespaces"},
			Verbs:     []string{"list"},
		},
		{
			APIGroups: []string{"storage.k8s.io"},
			Resources: []string{"storageclasses"},
			Verbs:     []string{"get", "list"},
		},
	}

	TaintCriticalAddonsOnly = "CriticalAddonsOnly"
	TaintControlPlane       = "node-role.kubernetes.io/control-plane"
	TolerationControlPlane  = []corev1.Toleration{
		{
			Key:      TaintCriticalAddonsOnly,
			Operator: corev1.TolerationOpExists,
		},
		{
			Key:      TaintControlPlane,
			Operator: corev1.TolerationOpExists,
			Effect:   corev1.TaintEffectNoSchedule,
		},
	}
)

type EventClient interface {
	List(ctx context.Context, opts metav1.ListOptions) (*corev1.EventList, error)
}

type PodClient interface {
	List(ctx context.Context, opts metav1.ListOptions) (*corev1.PodList, error)
}

type DeploymentClient interface {
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*appsv1.Deployment, error)
}

type NamespaceClient interface {
	Get(context.Context, string, metav1.GetOptions) (*corev1.Namespace, error)
	Create(context.Context, *corev1.Namespace, metav1.CreateOptions) (*corev1.Namespace, error)
	Patch(ctx context.Context, name string, pt types.PatchType, data []byte, opts metav1.PatchOptions, subresources ...string) (result *corev1.Namespace, err error)
	Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error
	List(ctx context.Context, opts metav1.ListOptions) (*corev1.NamespaceList, error)
}

type LeaseClient interface {
	Get(context.Context) (*resourcelock.LeaderElectionRecord, []byte, error)
	Create(context.Context, resourcelock.LeaderElectionRecord) error
	Update(context.Context, resourcelock.LeaderElectionRecord) error
	RecordEvent(string)
	Identity() string
	Describe() string
}

type NodeClient interface {
	Get(context.Context, string, metav1.GetOptions) (*corev1.Node, error)
	List(context.Context, metav1.ListOptions) (*corev1.NodeList, error)
	Update(context.Context, *corev1.Node, metav1.UpdateOptions) (*corev1.Node, error)
}

type SvcClient interface {
	Get(context.Context, string, metav1.GetOptions) (*corev1.Service, error)
}

type StorageClassClient interface {
	List(context.Context, metav1.ListOptions) (*storagev1.StorageClassList, error)
	Get(context.Context, string, metav1.GetOptions) (*storagev1.StorageClass, error)
	Patch(context.Context, string, types.PatchType, []byte, metav1.PatchOptions, ...string) (*storagev1.StorageClass, error)
}

type ServiceAccountClient interface {
	Apply(context.Context, *confCorev1.ServiceAccountApplyConfiguration, metav1.ApplyOptions) (*corev1.ServiceAccount, error)
	List(ctx context.Context, opts metav1.ListOptions) (*corev1.ServiceAccountList, error)
	Create(ctx context.Context, serviceAccount *corev1.ServiceAccount, opts metav1.CreateOptions) (*corev1.ServiceAccount, error)
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*corev1.ServiceAccount, error)
	Delete(context.Context, string, metav1.DeleteOptions) error
}

type SecretClient interface {
	Get(context.Context, string, metav1.GetOptions) (*corev1.Secret, error)
	Create(ctx context.Context, secret *corev1.Secret, opts metav1.CreateOptions) (*corev1.Secret, error)
	Apply(context.Context, *confCorev1.SecretApplyConfiguration, metav1.ApplyOptions) (*corev1.Secret, error)
	Delete(context.Context, string, metav1.DeleteOptions) error
}

type ClusterRoleClient interface {
	Get(context.Context, string, metav1.GetOptions) (*rbacv1.ClusterRole, error)
	List(context.Context, metav1.ListOptions) (*rbacv1.ClusterRoleList, error)
	Patch(context.Context, string, types.PatchType, []byte, metav1.PatchOptions, ...string) (*rbacv1.ClusterRole, error)
	Apply(context.Context, *confRbacv1.ClusterRoleApplyConfiguration, metav1.ApplyOptions) (*rbacv1.ClusterRole, error)
	Create(ctx context.Context, clusterRole *rbacv1.ClusterRole, opts metav1.CreateOptions) (*rbacv1.ClusterRole, error)
}

type ClusterRoleBindingClient interface {
	List(context.Context, metav1.ListOptions) (*rbacv1.ClusterRoleBindingList, error)
	Create(ctx context.Context, clusterRoleBinding *rbacv1.ClusterRoleBinding, opts metav1.CreateOptions) (*rbacv1.ClusterRoleBinding, error)
}

type RoleClient interface {
	Apply(context.Context, *confRbacv1.RoleApplyConfiguration, metav1.ApplyOptions) (*rbacv1.Role, error)
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*rbacv1.Role, error)
}

type RoleBindingClient interface {
	Apply(context.Context, *confRbacv1.RoleBindingApplyConfiguration, metav1.ApplyOptions) (*rbacv1.RoleBinding, error)
	List(ctx context.Context, opts metav1.ListOptions) (*rbacv1.RoleBindingList, error)
	Create(ctx context.Context, roleBinding *rbacv1.RoleBinding, opts metav1.CreateOptions) (*rbacv1.RoleBinding, error)
	Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error
}

type ResourceQuotaClient interface {
	List(ctx context.Context, opts metav1.ListOptions) (*corev1.ResourceQuotaList, error)
	Create(ctx context.Context, resourceQuota *corev1.ResourceQuota, opts metav1.CreateOptions) (*corev1.ResourceQuota, error)
	Patch(ctx context.Context, name string, pt types.PatchType, data []byte, opts metav1.PatchOptions, subresources ...string) (result *corev1.ResourceQuota, err error)
}

type Helper struct {
	clientset     *kubernetes.Clientset
	LeaseID       string
	LeaseCallback leaderelection.LeaderCallbacks

	EventClient
	PodClient
	DeploymentClient
	NamespaceClient
	NodeClient
	SvcClient
	StorageClassClient
	ServiceAccountClient
	SecretClient
	RoleClient
	RoleBindingClient
	ClusterRoleClient
	ClusterRoleBindingClient
	LeaseClient
	ResourceQuotaClient

	Options
}

func (h *Helper) SetAuth() error {
	var err error

	switch h.Auth.Type {
	case InClusterAuth:
		h.Auth.RestConf, err = rest.InClusterConfig()
	case OutOfClusterAuth:
		h.Auth.RestConf, err = clientcmd.BuildConfigFromFlags("", h.Auth.FilePath)
	default:
		return fmt.Errorf("unsupported auth type: %s", h.Auth.Type)
	}
	if err != nil {
		return err
	}

	h.clientset, err = kubernetes.NewForConfig(h.Auth.RestConf)
	if err != nil {
		return err
	}

	return nil
}

func (h *Helper) SetEventClient() {
	h.EventClient = h.clientset.CoreV1().Events(h.Namespace)
}

func (h *Helper) SetPodClient() {
	h.PodClient = h.clientset.CoreV1().Pods(h.Namespace)
}

func (h *Helper) SetDeploymentClient() {
	h.DeploymentClient = h.clientset.AppsV1().Deployments(h.Namespace)
}

func (h *Helper) SetSVCClient() {
	h.SvcClient = h.clientset.CoreV1().Services(h.Namespace)
}

func (h *Helper) SetLeaseClient(id string, name string, namespace string) {
	h.LeaseID = id
	h.LeaseClient = &resourcelock.LeaseLock{
		LeaseMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
		},
		Client: h.clientset.CoordinationV1(),
		LockConfig: resourcelock.ResourceLockConfig{
			Identity: h.LeaseID,
		},
	}
}

func (h *Helper) SetNamespaceClient() {
	h.NamespaceClient = h.clientset.CoreV1().Namespaces()
}

func (h *Helper) SetNodeClient() {
	h.NodeClient = h.clientset.CoreV1().Nodes()
}

func (h *Helper) SetStorageClassClient() {
	h.StorageClassClient = h.clientset.StorageV1().StorageClasses()
}

func (h *Helper) SetServiceAccountClient(namespace string) {
	h.ServiceAccountClient = h.clientset.CoreV1().ServiceAccounts(namespace)
}

func (h *Helper) SetSecretClient(namespace string) {
	h.SecretClient = h.clientset.CoreV1().Secrets(namespace)
}

func (h *Helper) SetRoleClient(namespace string) {
	h.RoleClient = h.clientset.RbacV1().Roles(namespace)
}

func (h *Helper) SetRoleBindingClient(namespace string) {
	h.RoleBindingClient = h.clientset.RbacV1().RoleBindings(namespace)
}

func (h *Helper) SetClusterRoleClient() {
	h.ClusterRoleClient = h.clientset.RbacV1().ClusterRoles()
}

func (h *Helper) SetClusterRoleBindingClient() {
	h.ClusterRoleBindingClient = h.clientset.RbacV1().ClusterRoleBindings()
}

func (h *Helper) SetResourceQuotaClient(namespace string) {
	h.ResourceQuotaClient = h.clientset.CoreV1().ResourceQuotas(namespace)
}

func (h *Helper) ListEvent(opt metav1.ListOptions) (*corev1.EventList, error) {
	var err error
	var trialCount int

	for {
		if trialCount > h.Options.Retry {
			return nil, err
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		events, err := h.EventClient.List(ctx, opt)
		cancel()
		if err != nil {
			trialCount++
			continue
		}

		return events, nil
	}
}

func (h *Helper) ListPod(opt metav1.ListOptions) (*corev1.PodList, error) {
	var err error
	var trialCount int

	for {
		if trialCount > h.Options.Retry {
			return nil, err
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		pods, err := h.PodClient.List(ctx, opt)
		cancel()
		if err != nil {
			trialCount++
			continue
		}

		return pods, nil
	}
}

func (h *Helper) GetDeployment(name string) (*appsv1.Deployment, error) {
	var err error
	var trialCount int

	for {
		if trialCount > h.Options.Retry {
			return nil, err
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		deployment, err := h.DeploymentClient.Get(ctx, name, metav1.GetOptions{})
		cancel()
		if err != nil {
			trialCount++
			continue
		}

		return deployment, nil
	}
}

func (h *Helper) SetLeaseCron(schedule func()) {
	h.LeaseCallback = leaderelection.LeaderCallbacks{
		OnStartedLeading: func(ctx context.Context) {
			schedule()
		},
		OnStoppedLeading: func() {
		},
		OnNewLeader: func(identity string) {
			if identity == h.LeaseID {
				return
			}
		},
	}
}

func (h *Helper) RunLeaseCron(ctx *context.Context) {
	LeaseRun(
		*ctx,
		leaderelection.LeaderElectionConfig{
			Lock:            h.LeaseClient,
			ReleaseOnCancel: true,
			LeaseDuration:   30 * time.Second,
			RenewDeadline:   15 * time.Second,
			RetryPeriod:     5 * time.Second,
			Callbacks:       h.LeaseCallback,
		},
	)
}

func (h *Helper) IsNamespaceExist(namespace string) bool {
	var trialCount int

	for {
		if trialCount > h.Options.Retry {
			return false
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		ns, err := h.NamespaceClient.Get(ctx, namespace, metav1.GetOptions{})
		cancel()
		if err != nil {
			trialCount++
			continue
		}

		if ns.Status.Phase != "Active" {
			trialCount++
			continue
		}

		return true
	}
}

func (h *Helper) GetNamespace(namespace string) (*corev1.Namespace, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.NamespaceClient.Get(ctx, namespace, metav1.GetOptions{})
}

func (h *Helper) ListNamespace(opt metav1.ListOptions) (*corev1.NamespaceList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.NamespaceClient.List(ctx, opt)
}

func (h *Helper) CreateNamespace(metadata metav1.ObjectMeta) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	spec := &corev1.Namespace{ObjectMeta: metadata}
	_, err := h.NamespaceClient.Create(ctx, spec, metav1.CreateOptions{})
	if err != nil {
		return err
	}

	return nil
}

func (h *Helper) PatchNamespace(namespace string, patchData []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	_, err := h.NamespaceClient.Patch(
		ctx,
		namespace,
		types.StrategicMergePatchType,
		patchData,
		metav1.PatchOptions{},
	)
	if err != nil {
		return err
	}

	return nil
}

func (h *Helper) DeleteNamespace(namespace string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	wait120s := int64(120)
	err := h.NamespaceClient.Delete(ctx, namespace, metav1.DeleteOptions{GracePeriodSeconds: &wait120s})
	if err != nil {
		return err
	}

	return nil
}

func (h *Helper) GetServiceAccount(name string) (*corev1.ServiceAccount, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ServiceAccountClient.Get(ctx, name, metav1.GetOptions{})
}

func (h *Helper) ListServiceAccount(opt metav1.ListOptions) (*corev1.ServiceAccountList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ServiceAccountClient.List(ctx, opt)
}

func (h *Helper) CreateServiceAccount(metadata metav1.ObjectMeta) (*corev1.ServiceAccount, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ServiceAccountClient.Create(
		ctx,
		&corev1.ServiceAccount{ObjectMeta: metadata},
		metav1.CreateOptions{},
	)
}

func (h *Helper) DeleteServiceAccount(name string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ServiceAccountClient.Delete(ctx, name, metav1.DeleteOptions{})
}

func (h *Helper) GetTokenSecret(secretName string) (*corev1.Secret, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.SecretClient.Get(
		ctx,
		secretName,
		metav1.GetOptions{},
	)
}

func (h *Helper) GetSecret(secretName string) (*corev1.Secret, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.SecretClient.Get(
		ctx,
		secretName,
		metav1.GetOptions{},
	)
}

func (h *Helper) CreateTokenSecret(secretName, serviceAccountName string) (*corev1.Secret, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.SecretClient.Create(
		ctx,
		genTokenSecretOpts(secretName, serviceAccountName),
		metav1.CreateOptions{},
	)
}

func (h *Helper) DeleteSecret(secretName string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.SecretClient.Delete(ctx, secretName, metav1.DeleteOptions{})
}

func (h *Helper) CreateRoleBinding(metadata metav1.ObjectMeta, roleRef *rbacv1.RoleRef, subjects []rbacv1.Subject) (*rbacv1.RoleBinding, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.RoleBindingClient.Create(
		ctx,
		&rbacv1.RoleBinding{
			ObjectMeta: metadata,
			RoleRef:    *roleRef,
			Subjects:   subjects,
		},
		metav1.CreateOptions{},
	)
}

func (h *Helper) ListRoleBindings(opt metav1.ListOptions) (*rbacv1.RoleBindingList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.RoleBindingClient.List(ctx, opt)
}

func (h *Helper) DeleteRoleBindings(username string, namespaces []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	for _, namespace := range namespaces {
		h.SetRoleBindingClient(namespace)
		err := h.RoleBindingClient.Delete(ctx, username, metav1.DeleteOptions{})
		if err != nil {
			return err
		}
	}

	return nil
}

func (h *Helper) DeleteRoleBindingsIfTheServiceAccountIsIncluded(username, namespace string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	list, err := h.RoleBindingClient.List(ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	for _, roleBinding := range list.Items {
		for _, subject := range roleBinding.Subjects {
			if !IsBoundServiceAccount(subject, username, namespace) {
				continue
			}

			h.SetRoleBindingClient(roleBinding.Namespace)
			err := h.RoleBindingClient.Delete(ctx, roleBinding.Name, metav1.DeleteOptions{})
			if err != nil {
				return err
			}

			break
		}
	}

	return nil
}
func (h *Helper) ListClusterRoleBinding(opt metav1.ListOptions) (*rbacv1.ClusterRoleBindingList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ClusterRoleBindingClient.List(ctx, opt)
}

func (h *Helper) GetClusterRole(name string) (*rbacv1.ClusterRole, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ClusterRoleClient.Get(ctx, name, metav1.GetOptions{})
}

func (h *Helper) CreateClusterRole(name string, rbacRules []rbacv1.PolicyRule) (*rbacv1.ClusterRole, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ClusterRoleClient.Create(
		ctx,
		&rbacv1.ClusterRole{
			ObjectMeta: metav1.ObjectMeta{Name: name},
			Rules:      rbacRules,
		},
		metav1.CreateOptions{},
	)
}

func (h *Helper) CreateClusterRoleBinding(metaData metav1.ObjectMeta, roleRef rbacv1.RoleRef, subjects []rbacv1.Subject) (*rbacv1.ClusterRoleBinding, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ClusterRoleBindingClient.Create(
		ctx,
		&rbacv1.ClusterRoleBinding{
			ObjectMeta: metaData,
			RoleRef:    roleRef,
			Subjects:   subjects,
		},
		metav1.CreateOptions{},
	)
}

func (h *Helper) GetNode(name string) (*corev1.Node, error) {
	var err error
	var trialCount int

	for {
		if trialCount > h.Options.Retry {
			return nil, err
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		node, err := h.NodeClient.Get(ctx, name, metav1.GetOptions{})
		cancel()
		if err != nil {
			trialCount++
			continue
		}

		return node, nil
	}
}

func (h *Helper) UpdateNode(node *corev1.Node) (*corev1.Node, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.NodeClient.Update(ctx, node, metav1.UpdateOptions{})
}

func (h *Helper) ListNodes() (*corev1.NodeList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.NodeClient.List(ctx, metav1.ListOptions{})
}

func (h *Helper) GetNodeIP(nodeName string, addrType string) (string, error) {
	node, err := h.GetNode(nodeName)
	if err != nil {
		return "", err
	}

	for _, addr := range node.Status.Addresses {
		if addr.Type == corev1.NodeAddressType(addrType) {
			return addr.Address, nil
		}
	}

	return "", fmt.Errorf("can't find the node ip by specified addr type(%s)", addrType)
}

func (h *Helper) GetSVC(name string) (*corev1.Service, error) {
	var err error
	var trialCount int

	for {
		if trialCount > h.Options.Retry {
			return nil, err
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		svc, err := h.SvcClient.Get(ctx, name, metav1.GetOptions{})
		cancel()
		if err != nil {
			trialCount++
			continue
		}

		return svc, nil
	}
}

func (h *Helper) GetSVCNodePortByTargetPort(svcName string, targetPort int) (int, error) {
	svc, err := h.GetSVC(svcName)
	if err != nil {
		return 0, err
	}

	for _, port := range svc.Spec.Ports {
		if port.TargetPort.IntValue() == 8080 {
			return int(port.NodePort), nil
		}
	}

	return 0, fmt.Errorf("can't find the node port by specified target port(%d)", targetPort)
}

func (h *Helper) PatchClusterRole(name string, dataToPatch []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	_, err := h.ClusterRoleClient.Patch(
		ctx,
		name,
		types.JSONPatchType,
		dataToPatch,
		metav1.PatchOptions{},
	)
	if err != nil {
		return errors.Wrapf(err, "Failed to patch cluster role: %s", name)
	}

	return nil
}

func (h *Helper) GetRole(name string) (*rbacv1.Role, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.RoleClient.Get(ctx, name, metav1.GetOptions{})
}

func (h *Helper) getDefaultStorageClasses(list *storagev1.StorageClassList) []storagev1.StorageClass {
	defaultList := []storagev1.StorageClass{}
	for _, sc := range list.Items {
		value, found := sc.Annotations["storageclass.kubernetes.io/is-default-class"]
		if !found {
			continue
		}

		if value != "" {
			defaultList = append(defaultList, sc)
		}
	}

	return defaultList
}

func (h *Helper) PatchStorageClasses(storageClasses []storagev1.StorageClass, patchData []byte) error {
	for _, sc := range storageClasses {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
		defer cancel()

		_, err := h.StorageClassClient.Patch(
			ctx,
			sc.Name,
			types.StrategicMergePatchType,
			patchData,
			metav1.PatchOptions{},
		)
		if err != nil {
			return errors.Wrapf(err, "Failed to patch StorageClass: %s", sc.Name)
		}
	}

	return nil
}

func (h *Helper) ListStorageClasses() (*storagev1.StorageClassList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	return h.StorageClassClient.List(ctx, metav1.ListOptions{})
}

func (h *Helper) GetStorageClass(name string) (*storagev1.StorageClass, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	return h.StorageClassClient.Get(ctx, name, metav1.GetOptions{})
}

func (h *Helper) DisableCurrentDefaultStorageClasses() error {
	list, err := h.ListStorageClasses()
	if err != nil {
		return errors.Wrapf(err, "Failed to list storage classes")
	}

	defaultList := h.getDefaultStorageClasses(list)
	patchData, err := genPatchToToggleDefaultStorageClass("false")
	if err != nil {
		return errors.Wrapf(err, "Failed to generate storage class patch data")
	}

	return h.PatchStorageClasses(defaultList, patchData)
}

func (h *Helper) SetDefaultStorageClass(name string) error {
	patchData, err := genPatchToToggleDefaultStorageClass("true")
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	_, err = h.StorageClassClient.Patch(
		ctx,
		name,
		types.StrategicMergePatchType,
		patchData,
		metav1.PatchOptions{},
	)
	if err != nil {
		return errors.Wrapf(err, "Failed to set default storage class: %s", name)
	}

	return nil
}

func (h *Helper) ListResourceQuota(opts metav1.ListOptions) (*corev1.ResourceQuotaList, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ResourceQuotaClient.List(ctx, opts)
}

func (h *Helper) CreateResourceQuota(name string, resourceQuota *corev1.ResourceQuota) (*corev1.ResourceQuota, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	return h.ResourceQuotaClient.Create(
		ctx,
		resourceQuota,
		metav1.CreateOptions{},
	)
}

func (h *Helper) UpdateResourceQuota(name string, patchData []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	_, err := h.ResourceQuotaClient.Patch(ctx, name, types.StrategicMergePatchType, patchData, metav1.PatchOptions{})
	if err != nil {
		return err
	}

	return nil
}

func overrideOptions(opts *Options, options []Option) *Options {
	for _, opt := range options {
		opt(opts)
	}

	return opts
}

func newHelper(opts *Options) (*Helper, error) {
	h := &Helper{Options: *opts}
	err := h.SetAuth()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to set auth")
	}

	return h, nil
}

func initOptions(opts []Option) *Options {
	defaultOpts := &Options{}
	return overrideOptions(defaultOpts, opts)
}

func NewClient(opts ...Option) (*Helper, error) {
	options := initOptions(opts)
	return newHelper(options)
}

func genTokenSecretOpts(secretName, serviceAccountName string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: secretName,
			Annotations: map[string]string{
				"kubernetes.io/service-account.name": serviceAccountName,
			},
		},
		Type: corev1.SecretTypeServiceAccountToken,
	}
}
