package helm

import (
	"cubectl/util/kube"

	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart"
	"helm.sh/helm/v3/pkg/cli"
)

var (
	Opts *Options
)

type Option func(*Options)

type Options struct {
	Release   string
	ChartPath string

	Chart           *chart.Chart
	Values          map[string]interface{}
	CreateNamespace bool

	EnvConfig  *cli.EnvSettings
	ActConfig  *action.Configuration
	KubeConfig kube.Options
}

func Release(name string) Option {
	return func(o *Options) {
		o.Release = name
	}
}

func ChartPath(path string) Option {
	return func(o *Options) {
		o.ChartPath = path
	}
}

func CreateNamespace(enabled bool) Option {
	return func(o *Options) {
		o.CreateNamespace = enabled
	}
}

func EnvConfig(env *cli.EnvSettings) Option {
	return func(o *Options) {
		o.EnvConfig = env
	}
}

func ActConfig(act *action.Configuration) Option {
	return func(o *Options) {
		o.ActConfig = act
	}
}

func KubeConfig(kube kube.Options) Option {
	return func(o *Options) {
		o.KubeConfig = kube
	}
}

func AuthType(authType string) Option {
	return func(o *Options) {
		o.KubeConfig.Auth.Type = authType
	}
}

func AuthFile(file string) Option {
	return func(o *Options) {
		o.KubeConfig.FilePath = file
	}
}
