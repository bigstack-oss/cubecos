package config

import (
	"cubectl/util/aws"
	"cubectl/util/kube"
	"cubectl/util/openstack"
	cubeSettings "cubectl/util/settings"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/gophercloud/gophercloud"
	"github.com/pkg/errors"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	kubeErr "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/clientcmd"
	clientcmdapi "k8s.io/client-go/tools/clientcmd/api"
)

type UserInfo struct {
	Name          string       `yaml:"name"`
	CreatedAt     string       `yaml:"createdAt"`
	Permissions   []Permission `yaml:"permissions"`
	KubeConfigUrl string       `yaml:"kubeConfigUrl"`
}

type Permission struct {
	Namespace string `yaml:"namespace"`
	Kind      string `yaml:"kind"`
	Role      string `yaml:"role"`
}

func k3sListUsers() error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	kubeCli.SetServiceAccountClient(kube.DefaultNamespace)
	serviceAccounts, err := kubeCli.ListServiceAccount(defaultCubeManagedListOpts)
	if err != nil {
		return err
	}

	kubeCli.SetNamespaceClient()
	namespaces, err := kubeCli.ListNamespace(defaultCubeManagedListOpts)
	if err != nil {
		return err
	}

	if len(serviceAccounts.Items) != 0 {
		listUserWithNamespaces(serviceAccounts, namespaces)
	}

	return nil
}

func k3sGetUser(username string) error {
	err := initDependencyClients()
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetServiceAccountClient(kube.DefaultNamespace)
	sa, err := kubeCli.GetServiceAccount(username)
	if err != nil {
		return err
	}

	permissions, err := getUserRbacRoleRefs(username)
	if err != nil {
		return err
	}

	url, err := s3Cli.GenPresignedUrl(k3sBucket, s3ObjectKey(username), day*7)
	if err != nil {
		return err
	}

	showUserInfo(UserInfo{
		Name:          sa.Name,
		CreatedAt:     sa.CreationTimestamp.String(),
		Permissions:   permissions,
		KubeConfigUrl: url,
	})

	return nil
}

func k3sCreateUser(username string, namespaces []string) error {
	err := initDependencyClients()
	if err != nil {
		return errors.WithStack(err)
	}

	conf, err := initUserRbac(username, namespaces)
	if err != nil {
		return errors.WithStack(err)
	}

	url, err := genConfUrl(username, conf)
	if err != nil {
		return errors.WithStack(err)
	}

	fmt.Printf("URL to download Kube config: %s\n", url)
	fmt.Printf("Caution: The URL will be expired in 7 days. Please download it as soon as possible\n")

	return nil
}

func k3sUpdateUser(username string) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	switch operation {
	case "add":
		_, err = initUserRbac(username, namespaces)
	case "remove":
		kubeCli.SetRoleBindingClient("")
		err = kubeCli.DeleteRoleBindings(username, namespaces)
	default:
		err = fmt.Errorf(
			"invalid operation(%s) to update user",
			operation,
		)
	}
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func k3sDeleteUser(username string) error {
	err := initDependencyClients()
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetServiceAccountClient(kube.DefaultNamespace)
	err = kubeCli.DeleteServiceAccount(username)
	if err != nil {
		return errors.WithStack(err)
	}

	kubeCli.SetRoleBindingClient("")
	err = kubeCli.DeleteRoleBindingsIfTheServiceAccountIsIncluded(username, kube.DefaultNamespace)
	if err != nil {
		return errors.WithStack(err)
	}

	err = s3Cli.DeleteObject(k3sBucket, s3ObjectKey(username))
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func s3ObjectKey(username string) string {
	return fmt.Sprintf("%s/config", username)
}

func listUserWithNamespaces(serviceAccounts *corev1.ServiceAccountList, namespaces *corev1.NamespaceList) {
	if !noHeader {
		fmt.Printf("%-20s %-20s\n", "NAME", "NAMESPACES")
	}

	for _, serviceAccount := range serviceAccounts.Items {
		if noNamespace {
			fmt.Println(serviceAccount.Name)
			continue
		}

		aggregateAndShowFormattedUserNamespaceInfo(serviceAccount, namespaces)
	}
}

func showUserInfo(userInfo UserInfo) {
	b, err := yaml.Marshal(userInfo)
	if err != nil {
		zap.L().Error("Failed to marshal user info", zap.Error(err))
		return
	}

	fmt.Println(string(b))
}

func checkAndAddRoleBindings(permissions *[]Permission, username string, roleBindings *rbacv1.RoleBindingList) {
	for _, roleBinding := range roleBindings.Items {
		for _, subject := range roleBinding.Subjects {
			if !kube.IsBoundServiceAccount(subject, username, kube.DefaultNamespace) {
				continue
			}

			*permissions = append(
				*permissions,
				Permission{
					Namespace: roleBinding.Namespace,
					Kind:      roleBinding.RoleRef.Kind,
					Role:      roleBinding.RoleRef.Name,
				},
			)
		}
	}
}

func getUserRbacRoleRefs(username string) ([]Permission, error) {
	permissions := []Permission{}

	kubeCli.SetNamespaceClient()
	namespaces, err := kubeCli.ListNamespace(defaultCubeManagedListOpts)
	if err != nil {
		return nil, err
	}

	for _, namespace := range namespaces.Items {
		kubeCli.SetRoleBindingClient(namespace.Name)
		roleBindings, err := kubeCli.ListRoleBindings(defaultCubeManagedListOpts)
		if err != nil {
			return nil, err
		}

		checkAndAddRoleBindings(
			&permissions,
			username,
			roleBindings,
		)
	}

	return permissions, nil
}

func genServiceAccountDefaultSubjects(username string) []rbacv1.Subject {
	return []rbacv1.Subject{
		{
			Kind:      kube.KindServiceAccount,
			Name:      username,
			Namespace: kube.DefaultNamespace,
		},
	}
}

func attachAdminNamespaceClusterRole(username string, namespaces []string) error {
	metaData := metav1.ObjectMeta{
		Name:   username,
		Labels: defaultCubeManagedKeyPairMap,
	}

	for _, namespace := range namespaces {
		kubeCli.SetRoleBindingClient(namespace)
		_, err := kubeCli.CreateRoleBinding(
			metaData,
			kube.RoleRefAdminNamespace,
			genServiceAccountDefaultSubjects(username),
		)
		if err == nil {
			continue
		}

		if !kubeErr.IsAlreadyExists(err) {
			return err
		}
	}

	return nil
}

func attachListNamespaceClusterRole(username string) error {
	metaData := metav1.ObjectMeta{
		Name:   username,
		Labels: defaultCubeManagedKeyPairMap,
	}

	kubeCli.SetClusterRoleBindingClient()
	_, err := kubeCli.CreateClusterRoleBinding(
		metaData,
		kube.RoleRefCubeUser,
		genServiceAccountDefaultSubjects(username),
	)
	if err == nil {
		return nil
	}

	if !kubeErr.IsAlreadyExists(err) {
		return err
	}

	return nil
}

func applyBindings(username string, namespaces []string) error {
	err := attachListNamespaceClusterRole(username)
	if err != nil {
		return errors.Wrapf(err, "Failed to attach list-namespace cluster role")
	}

	err = attachAdminNamespaceClusterRole(username, namespaces)
	if err != nil {
		return errors.Wrapf(err, "Failed to attach admin-namespace cluster role")
	}

	return nil
}

func applyDefaultClusterRoles() error {
	kubeCli.SetClusterRoleClient()
	_, err := kubeCli.CreateClusterRole(kube.ClusterRoleCubeUser, kube.CubeUser)
	if err == nil {
		return nil
	}

	if !kubeErr.IsAlreadyExists(err) {
		return err
	}

	return nil
}

func getUserToken(username string) (string, error) {
	kubeCli.SetSecretClient(kube.DefaultNamespace)
	secret, err := kubeCli.GetTokenSecret(username)
	if err != nil {
		return "", err
	}

	token, found := secret.Data["token"]
	if !found {
		return "", errors.New("Token not found")
	}

	return string(token), nil
}

func applyServiceAccount(username string) error {
	kubeCli.SetServiceAccountClient(kube.DefaultNamespace)
	_, err := kubeCli.CreateServiceAccount(metav1.ObjectMeta{
		Name:   username,
		Labels: defaultCubeManagedKeyPairMap,
	})
	if err != nil {
		if !kubeErr.IsAlreadyExists(err) {
			return err
		}
	}

	kubeCli.SetSecretClient(kube.DefaultNamespace)
	_, err = kubeCli.CreateTokenSecret(username, username)
	if err != nil {
		if !kubeErr.IsAlreadyExists(err) {
			return err
		}
	}

	return nil
}

func uploadAccessConf(bucketName, username string, config *clientcmdapi.Config) (string, error) {
	key := s3ObjectKey(username)
	body, err := clientcmd.Write(*config)
	if err != nil {
		return "", err
	}

	_, err = s3Cli.PutObject(bucketName, key, body)
	if err != nil {
		return "", err
	}

	return s3Cli.GenPresignedUrl(bucketName, key, day*7)
}

func syncStorageAccess() error {
	userId, err := openstack.GetUserIdByName(identityCli, "admin")
	if err != nil {
		return err
	}

	projectId, err := openstack.GetProjectIdByName(identityCli, "admin")
	if err != nil {
		return err
	}

	_, err = openstack.CreateEc2Credential(
		identityCli,
		userId,
		projectId,
		aws.S3DefaultAccessKey,
		aws.S3DefaultSecretKey,
	)
	if err == nil {
		return nil
	}
	_, is409 := err.(gophercloud.ErrDefault409)
	if !is409 {
		return err
	}

	return nil
}

func syncBucketStore(bucketName string) error {
	_, err := s3Cli.CreateBucket(bucketName)
	if err == nil {
		return nil
	}

	var isBucketAlreadyExists *types.BucketAlreadyExists
	if !errors.As(err, &isBucketAlreadyExists) {
		return err
	}

	return nil
}

func initUserAuthConfig(username, token string, config *clientcmdapi.Config) {
	cluster := kube.DefaultNamespace
	config.Clusters[cluster].Server = fmt.Sprintf("https://%s:%d", cubeSettings.GetControllerIp(), k3sPort)
	config.AuthInfos = make(map[string]*clientcmdapi.AuthInfo)
	config.AuthInfos[username] = &clientcmdapi.AuthInfo{Token: token}
	config.Contexts = make(map[string]*clientcmdapi.Context)
	config.Contexts["default"] = &clientcmdapi.Context{
		Cluster:   "default",
		Namespace: kube.DefaultNamespace,
		AuthInfo:  username,
	}
}

func genAccessConf(username string) (*clientcmdapi.Config, error) {
	config, err := clientcmd.LoadFromFile(k3sConfigFile)
	if err != nil {
		return nil, err
	}

	token, err := getUserToken(username)
	if err != nil {
		return nil, err
	}

	initUserAuthConfig(username, token, config)
	return config, nil
}

func genConfUrl(username string, conf *clientcmdapi.Config) (string, error) {
	err := syncStorageAccess()
	if err != nil {
		return "", err
	}

	err = syncBucketStore(k3sBucket)
	if err != nil {
		return "", err
	}

	return uploadAccessConf(
		k3sBucket,
		username,
		conf,
	)
}

func initUserRbac(username string, namespaces []string) (*clientcmdapi.Config, error) {
	err := applyServiceAccount(username)
	if err != nil {
		return nil, err
	}

	err = applyDefaultClusterRoles()
	if err != nil {
		return nil, err
	}

	err = applyBindings(username, namespaces)
	if err != nil {
		return nil, err
	}

	return genAccessConf(username)
}
