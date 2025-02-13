package kube

import rbacv1 "k8s.io/api/rbac/v1"

func IsBoundServiceAccount(subject rbacv1.Subject, username, namespace string) bool {
	return subject.Kind == "ServiceAccount" && subject.Name == username && subject.Namespace == namespace
}
