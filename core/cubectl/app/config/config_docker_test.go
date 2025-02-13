package config

import (
	"fmt"
	"os"
	"path"
	"testing"

	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeTesting "cubectl/util/testing"
)

func runDockerRegistryContainer(ns *cubeTesting.Namespace) (*cubeTesting.Container, error) {
	c := ns.NewContainer("docker.io/library/registry:2")
	if err := c.RunDetach(
		[]string{
			"-p", fmt.Sprintf("%d:%d", dockerRegistryPort, 5000),
			"-v", dockerRegistryVolume + ":/var/lib/registry",
		},
	); err != nil {
		return nil, err
	}

	if err := util.CheckService("localhost", dockerRegistryPort, 10); err != nil {
		return nil, err
	}

	return c, nil
}

func TestConfigDockerWriteConfig(t *testing.T) {
	t.Parallel()

	testClean := func() {
		os.RemoveAll(path.Dir(dockerConfigFile))
	}
	testClean()
	t.Cleanup(testClean)

	registryHost := "test-reg.org"
	if err := dockerWriteConf(registryHost); err != nil {
		t.Fatal(err)
	}

	viperJson := viper.New()
	viperJson.SetConfigType("json")
	viperJson.SetConfigFile(dockerConfigFile)
	if err := viperJson.ReadInConfig(); err != nil {
		t.Fatal(err)
	}

	assert.Contains(t, viperJson.GetStringSlice("insecure-registries"), fmt.Sprintf("%s:%d", registryHost, dockerRegistryPort))
}

func TestConfigDockerCheckImage(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	if testClean(t, func() {
		ns.CleanupContainers()
	}) {
		return
	}

	if _, err := runDockerRegistryContainer(ns); err != nil {
		t.Fatal(err)
	}

	// Current dir: /root/workspace/cube/core/cubectl/app/config
	if err := dockerCheckImage("../../../k3s/images.txt"); err != nil {
		t.Fatal(err)
	}
}
