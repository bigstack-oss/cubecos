package kube

import (
	"encoding/json"
	"fmt"

	"github.com/pkg/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
)

var (
	Opts *Options
)

type Option func(*Options)

type Options struct {
	Namespace string
	URL       string
	Auth

	metav1.ListOptions

	Fetch
}

type Fetch struct {
	Interval int
	Retry    int
}

type Auth struct {
	Type     string
	Token    string
	FilePath string
	CAFile   string
	RestConf *rest.Config
}

func Namespace(name string) Option {
	return func(o *Options) {
		o.Namespace = name
	}
}

func AuthType(authType string) Option {
	return func(o *Options) {
		o.Auth.Type = authType
	}
}

func AuthFile(file string) Option {
	return func(o *Options) {
		o.FilePath = file
	}
}

func genPatchToToggleDefaultStorageClass(toggle string) ([]byte, error) {
	if toggle != "true" && toggle != "false" {
		return nil, fmt.Errorf("invalid toggle value: %s", toggle)
	}

	patchData := map[string]interface{}{
		"metadata": map[string]interface{}{
			"annotations": map[string]string{
				"storageclass.kubernetes.io/is-default-class": toggle,
			},
		},
	}

	b, err := json.Marshal(patchData)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to marshal toggle data for storage class")
	}

	return b, nil
}
