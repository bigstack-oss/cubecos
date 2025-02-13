package config

import (
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
	cubeTesting "cubectl/util/testing"
)

func runRancherContainer(ns *cubeTesting.Namespace) (*cubeTesting.Container, error) {
	if err := genSelfSignCerts(); err != nil {
		return nil, err
	}

	c := ns.NewContainer("localhost/bigstack/rancher:v2.5.7")
	if err := c.RunDetach([]string{
		"-p", fmt.Sprintf("%d:%d", k3sIngressHttpsPort, 443),
		//"--add-host=releases.rancher.com:127.0.0.1",
		"-v", certFile + ":/etc/rancher/ssl/cert.pem",
		"-v", keyFile + ":/etc/rancher/ssl/key.pem",
		"-v", certFile + ":/etc/rancher/ssl/cacerts.pem",
		"--privileged",
		//"--cgroupns=private",
	}); err != nil {
		return nil, err
	}

	if err := util.CheckService("localhost", k3sIngressHttpsPort, 10); err != nil {
		return nil, err
	}

	//time.Sleep(5 * time.Second)

	return c, nil
}

// func rancherRegistryTest(imgsFile string) error {
// 	var cmd *exec.Cmd
// 	cmd = exec.Command(rancherImagesScript, "pull", imgsFile)
// 	cmd.Dir = rancherDataDir
// 	if err := cmd.Run(); err != nil {
// 		return errors.WithStack(err)
// 	}

// 	if _, _, err := util.ExecCmd(rancherImagesScript, "push", strings.TrimSuffix(imgsFile, ".txt")); err != nil {
// 		return errors.WithStack(err)
// 	}

// 	// Test if images are pushed on registry
// 	if err := dockerCheckImage(imgsFile); err != nil {
// 		return errors.WithStack(err)
// 	}

// 	return nil
// }

// func TestConfigRancherRegistry(t *testing.T) {
// 	t.Parallel()

// 	ns := cubeTesting.ContainerNS(t.Name())
// 	testClean := func() {
// 		ns.CleanupContainers()
// 		os.RemoveAll(rancherDataDir)
// 	}
// 	testClean()
// 	t.Cleanup(testClean)

// 	registry := ns.NewContainer("registry:2")
// 	if err := registry.RunDetach([]string{
// 		"--publish=" + strconv.Itoa(dockerRegistryPort) + ":5000",
// 	}); err != nil {
// 		t.Fatal(err)
// 	}

// 	os.MkdirAll(rancherDataDir, 0755)
// 	if _, _, err := util.ExecCmd("ln", "-sf", "/root/workspace/cube/core/rancher/copy-images.sh", rancherDataDir); err != nil {
// 		t.Fatal(err)
// 	}

// 	t.Run("RancherBaseImages", func(t *testing.T) {
// 		t.SkipNow()
// 		t.Parallel()

// 		if _, _, err := util.ExecCmd("ln", "-sf", "/root/workspace/cube/core/rancher/images.txt", rancherDataDir); err != nil {
// 			t.Fatal(err)
// 		}

// 		if err := rancherRegistryTest(rancherImagesFile); err != nil {
// 			t.Fatal(err)
// 		}
// 	})

// 	t.Run("CustomImages", func(t *testing.T) {
// 		t.Parallel()

// 		if err := ioutil.WriteFile(
// 			rancherDataDir+"/test-images.txt", []byte(
// 				"busybox\n"+
// 					"rancher/pause:3.1\n",
// 			),
// 			0644,
// 		); err != nil {
// 			t.Fatal(err)
// 		}

// 		if err := rancherRegistryTest(rancherDataDir + "/test-images.txt"); err != nil {
// 			t.Fatal(err)
// 		}
// 	})

// }

func TestConfigRancher(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	if testClean(t, func() {
		ns.CleanupContainers()
		os.RemoveAll(path.Dir(keycloakSamlMetadataFile))
		os.RemoveAll(certsDir)
		resetHost()
	}) {
		return
	}

	localIP, err := getIfaceIP("eth0")
	if err != nil {
		t.Fatal(err)
	}

	if err := cubeSettings.LoadMap(
		map[string]string{
			"cubesys.role":       "control",
			"cubesys.management": "eth0",
			"net.if.addr.eth0":   localIP,
		},
	); err != nil {
		t.Fatal(err)
	}

	// For cube-controller
	if err := commitHost(); err != nil {
		t.Fatal(err)
	}

	if _, err := ns.RunEtcdContainer(); err != nil {
		t.Fatal(err)
	}

	if _, err := runRancherContainer(ns); err != nil {
		t.Fatal(err)
	}

	// os.MkdirAll(certsDir, 0755)
	// _ = ioutil.WriteFile(certFile, []byte{}, 0644)
	// _ = ioutil.WriteFile(keyFile, []byte{}, 0644)
	os.MkdirAll(path.Dir(keycloakSamlMetadataFile), 0755)
	ioutil.WriteFile(keycloakSamlMetadataFile, []byte{}, 0644)

	if err := terraformExec("apply", "rancher", "cube_controller="+cubeSettings.GetControllerIp()); err != nil {
		t.Fatal(err)
	}

	if err := rancherConfigInit(); err != nil {
		t.Fatal(err)
	}

	t.Run("CliLogin", func(t *testing.T) {
		t.Parallel()

		if err := rancherCliLogin(); err != nil {
			t.Fatal(err)
		}

		// Test server-url
		if out, _, err := util.ExecCmd(rancherCliBin,
			"settings", "get", "server-url",
			"--format", `{{.Setting.Value}}`,
		); err != nil {
			t.Fatal(err)
		} else {
			assert.Equal(t, fmt.Sprintf("https://%s:%d", localIP, k3sIngressHttpsPort), strings.TrimSuffix(out, "\n"))
		}
	})

	t.Run("CreateTemplate", func(t *testing.T) {
		t.Parallel()

		// if _, outErr, err := util.ExecCmd("cubectl", "config", "rancher",
		// 	"create-nodetemplate", "openstack-test",
		// 	"--openstack-config", `{"domainName": "default"}`,
		// )

		rancherCreateNodeTemplateOpts.openstackConfig = `{"domainName": "default"}`
		if err := cmdRancherCreateNodeTemplate.RunE(nil, []string{"openstack-test"}); err != nil {
			t.Fatal(err)
		} else {
			if result, err := rancherReq("GET",
				"/v3/nodeTemplates?name=openstack-test",
				``,
			); err != nil {
				t.Fatal(err)
			} else {
				assert.NotEmpty(t, result["data"])

				openstackConfig := result["data"].([]interface{})[0].(map[string]interface{})["openstackConfig"].(map[string]interface{})
				assert.Equal(t, "default", openstackConfig["domainName"])
			}
		}
	})
}
