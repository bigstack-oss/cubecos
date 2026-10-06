package config

import (
	"encoding/json"
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

	confFile := path.Join(t.TempDir(), "docker", "daemon.json")
	registryHost := "test-reg.org"
	if updated, err := dockerEnsureConf(confFile, registryHost); err != nil {
		t.Fatal(err)
	} else {
		assert.True(t, updated)
	}

	viperJson := viper.New()
	viperJson.SetConfigType("json")
	viperJson.SetConfigFile(confFile)
	if err := viperJson.ReadInConfig(); err != nil {
		t.Fatal(err)
	}

	assert.Contains(t, viperJson.GetStringSlice("insecure-registries"), fmt.Sprintf("%s:%d", registryHost, dockerRegistryPort))

	// byte for byte what nodes already carry, so an upgraded node regenerates the same file
	data, err := os.ReadFile(confFile)
	if err != nil {
		t.Fatal(err)
	}
	assert.Equal(t, "{\n  \"insecure-registries\": [\n    \"test-reg.org:5080\"\n  ]\n}", string(data))
}

func TestConfigDockerKeepSiteConfig(t *testing.T) {
	t.Parallel()

	// a support KB's daemon.json, written before the cluster is set up
	site := `{
  "bip": "172.30.0.1/24",
  "default-address-pools": [
    {
      "base": "172.31.0.0/16",
      "size": 24
    }
  ]
}
`
	confFile := path.Join(t.TempDir(), "daemon.json")
	if err := os.WriteFile(confFile, []byte(site), 0644); err != nil {
		t.Fatal(err)
	}

	if updated, err := dockerEnsureConf(confFile, "cc1"); err != nil {
		t.Fatal(err)
	} else {
		assert.True(t, updated)
	}

	var want, got map[string]interface{}
	if err := json.Unmarshal([]byte(site), &want); err != nil {
		t.Fatal(err)
	}
	want["insecure-registries"] = []interface{}{"cc1:5080"}
	data, err := os.ReadFile(confFile)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	assert.Equal(t, want, got)

	// listed now: left alone
	if updated, err := dockerEnsureConf(confFile, "cc1"); err != nil {
		t.Fatal(err)
	} else {
		assert.False(t, updated)
	}
	again, err := os.ReadFile(confFile)
	if err != nil {
		t.Fatal(err)
	}
	assert.Equal(t, data, again)
}

func TestConfigDockerAddRegistry(t *testing.T) {
	t.Parallel()

	// a registry of the site's own stays, and the cluster's is added after it
	confFile := path.Join(t.TempDir(), "daemon.json")
	if err := os.WriteFile(confFile, []byte(`{"insecure-registries": ["mirror.example:5000"]}`), 0644); err != nil {
		t.Fatal(err)
	}

	if updated, err := dockerEnsureConf(confFile, "cc1"); err != nil {
		t.Fatal(err)
	} else {
		assert.True(t, updated)
	}

	var got map[string]interface{}
	data, err := os.ReadFile(confFile)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	assert.Equal(t, []interface{}{"mirror.example:5000", "cc1:5080"}, got["insecure-registries"])
}

func TestConfigDockerBadConfig(t *testing.T) {
	t.Parallel()

	// a file docker cannot read either is reported, never replaced
	confFile := path.Join(t.TempDir(), "daemon.json")
	if err := os.WriteFile(confFile, []byte(`{"bip": `), 0644); err != nil {
		t.Fatal(err)
	}

	_, err := dockerEnsureConf(confFile, "cc1")
	assert.Error(t, err)

	data, err := os.ReadFile(confFile)
	if err != nil {
		t.Fatal(err)
	}
	assert.Equal(t, `{"bip": `, string(data))
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
