package kube

import (
	"context"
	"testing"

	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func clusterRoleBinding(name string, labels map[string]string, subjects ...rbacv1.Subject) *rbacv1.ClusterRoleBinding {
	return &rbacv1.ClusterRoleBinding{
		ObjectMeta: metav1.ObjectMeta{Name: name, Labels: labels},
		RoleRef:    rbacv1.RoleRef{APIGroup: "rbac.authorization.k8s.io", Kind: "ClusterRole", Name: "cube-user"},
		Subjects:   subjects,
	}
}

func serviceAccount(name, namespace string) rbacv1.Subject {
	return rbacv1.Subject{Kind: "ServiceAccount", Name: name, Namespace: namespace}
}

// k3s user_delete must drop the user's ClusterRoleBinding, and only bindings
// cube manages that name the user's ServiceAccount.
func TestDeleteClusterRoleBindingsIfTheServiceAccountIsIncluded(t *testing.T) {
	cube := map[string]string{"app.kubernetes.io/managed-by": "cube"}
	clientset := fake.NewSimpleClientset(
		clusterRoleBinding("u1", cube, serviceAccount("u1", "default")),
		clusterRoleBinding("u2", cube, serviceAccount("u2", "default")),
		clusterRoleBinding("u1-other-ns", cube, serviceAccount("u1", "kube-system")),
		clusterRoleBinding("not-cube", nil, serviceAccount("u1", "default")),
	)
	h := &Helper{ClusterRoleBindingClient: clientset.RbacV1().ClusterRoleBindings()}

	err := h.DeleteClusterRoleBindingsIfTheServiceAccountIsIncluded("u1", "default",
		metav1.ListOptions{LabelSelector: "app.kubernetes.io/managed-by=cube"})
	if err != nil {
		t.Fatalf("delete: %v", err)
	}

	list, err := clientset.RbacV1().ClusterRoleBindings().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	left := map[string]bool{}
	for _, b := range list.Items {
		left[b.Name] = true
	}
	if left["u1"] {
		t.Errorf("u1's binding is still there")
	}
	for _, name := range []string{"u2", "u1-other-ns", "not-cube"} {
		if !left[name] {
			t.Errorf("%s was deleted, want it kept", name)
		}
	}
}
