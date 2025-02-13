package helm

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"cubectl/util/kube"

	"github.com/pkg/errors"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/cli/values"
	"helm.sh/helm/v3/pkg/getter"
	"helm.sh/helm/v3/pkg/release"
)

const (
	Install   = "install"
	Upgrade   = "upgrade"
	Get       = "get"
	Uninstall = "uninstall"
)

var ()

type InstallClient interface {
	RunWithContext(context.Context, *chart.Chart, map[string]interface{}) (*release.Release, error)
}

type UpgradeClient interface {
	RunWithContext(context.Context, string, *chart.Chart, map[string]interface{}) (*release.Release, error)
}

type UninstallClient interface {
	Run(string) (*release.UninstallReleaseResponse, error)
}

type GetClient interface {
	Run(string) (*release.Release, error)
}

type Helper struct {
	GetClient
	InstallClient
	InstallClientPtr *action.Install
	UpgradeClient
	UninstallClient

	Options
}

type Tree struct {
	Branch         string
	SparseCheckout []string
}

func (h *Helper) SetAuth() error {
	h.EnvConfig = cli.New()

	switch h.KubeConfig.Auth.Type {
	case kube.InClusterAuth:
		h.EnvConfig.KubeAPIServer = h.KubeConfig.URL
		h.EnvConfig.KubeToken = h.KubeConfig.Auth.Token
		h.EnvConfig.KubeCaFile = h.KubeConfig.Auth.CAFile
	case kube.OutOfClusterAuth:
		h.EnvConfig.KubeConfig = h.KubeConfig.FilePath
	default:
		return fmt.Errorf("unsupported auth type: %s", h.KubeConfig.Auth.Type)
	}

	return nil
}

func (h *Helper) InitOperator(opType string) error {
	h.ActConfig = &action.Configuration{}
	err := h.ActConfig.Init(
		h.EnvConfig.RESTClientGetter(),
		"default",
		os.Getenv("HELM_DRIVER"),
		func(format string, v ...interface{}) {
			zap.S().Debugf(format, v...)
		},
	)
	if err != nil {
		return errors.Wrapf(err, "Failed to init helm action configuration")
	}

	switch strings.ToLower(opType) {
	case Install:
		installCli := action.NewInstall(h.ActConfig)
		installCli.CreateNamespace = h.CreateNamespace
		h.InstallClient = installCli
		h.InstallClientPtr = installCli
	case Upgrade:
		upgradeCli := action.NewUpgrade(h.ActConfig)
		upgradeCli.MaxHistory = 3
		h.UpgradeClient = upgradeCli
	case Get:
		h.GetClient = action.NewGet(h.ActConfig)
	case Uninstall:
		h.UninstallClient = action.NewUninstall(h.ActConfig)
	default:
		return fmt.Errorf("unsupported helm operation for helm: %s", opType)
	}

	return nil
}

func (h *Helper) InitApplyOperator() error {
	err := h.InitOperator(Install)
	if err != nil {
		return errors.Wrapf(err, "Failed to init install operator")
	}

	err = h.InitOperator(Upgrade)
	if err != nil {
		return errors.Wrapf(err, "Failed to init upgrade operator")
	}

	err = h.InitOperator(Get)
	if err != nil {
		return errors.Wrapf(err, "Failed to init get operator")
	}

	return nil
}

func (h *Helper) LoadChart(chartPath string) error {
	var err error
	h.Chart, err = loader.Load(chartPath)
	if err != nil {
		return errors.Wrapf(err, "Failed to load chart from path: %s", chartPath)
	}

	return nil
}

func (h *Helper) LoadRemoteChartTgz(url string) error {
	resp, err := http.Get(url)
	if err != nil {
		return errors.Wrapf(err, "Failed to get response from url: %s", url)
	}

	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return errors.Wrapf(err, "Failed to read response body from url: %s", url)
	}

	h.Chart, err = loader.LoadArchive(io.NopCloser(bytes.NewReader(data)))
	if err != nil {
		return errors.Wrapf(err, "Failed to load chart from url: %s", url)
	}

	return nil
}

func (h *Helper) LoadLocalChartTgz(path string) error {
	var err error
	h.Chart, err = loader.Load(path)
	if err != nil {
		return errors.Wrapf(err, "Failed to load chart from path: %s", path)
	}

	return nil
}

func (h *Helper) SetNamespace(namespace string) {
	h.InstallClientPtr.Namespace = namespace
	h.EnvConfig.SetNamespace(namespace)
}

func (h *Helper) Apply(release, namespace string) error {
	var err error
	var hasInstalled bool
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	h.SetNamespace(namespace)
	rel, err := h.GetClient.Run(release)
	hasInstalled = (err == nil) && (rel.Name == release)
	if hasInstalled {
		_, err = h.UpgradeClient.RunWithContext(ctx, release, h.Chart, h.Values)
		return errors.Wrapf(err, "Failed to upgrade release: %s", release)
	}

	h.InstallClientPtr.ReleaseName = release
	_, err = h.InstallClient.RunWithContext(ctx, h.Chart, h.Values)
	return err
}

func (h *Helper) Uninstall(releaseName string) error {
	_, err := h.UninstallClient.Run(releaseName)
	return err
}

func (h *Helper) LoadValueFromFile(file string) (map[string]interface{}, error) {
	b, err := os.ReadFile(file)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to read file: %s", file)
	}

	values := map[string]interface{}{}
	err = yaml.Unmarshal(b, &values)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to unmarshal values from file: %s", file)
	}

	return values, nil
}

func (h *Helper) OverrideDefaultValues(valuesToOverride values.Options) error {
	var err error
	defaultValues := getter.All(h.EnvConfig)
	h.Values, err = valuesToOverride.MergeValues(defaultValues)
	return err
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
