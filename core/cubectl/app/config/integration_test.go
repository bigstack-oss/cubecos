// +build itest

package config

import (
	"fmt"
	"os"
	"path"
	"sync"
	"testing"

	"github.com/pkg/errors"

	"cubectl/util"
	cubeTesting "cubectl/util/testing"
)

func createHAProxyToIngressService(extIP string) error {
	const yamlFmt = `
apiVersion: v1
kind: Service
metadata:
  name: test-haproxy
spec:
  externalIPs:
  - %s
  ports:
  - port: 443
    protocol: TCP
    targetPort: https
  selector:
    app.kubernetes.io/name: ingress-nginx
  type: ClusterIP		
`

	if _, outErr, err := util.ExecShf("echo '%s' | k3s kubectl apply -n %s -f -", fmt.Sprintf(yamlFmt, extIP), "ingress-nginx"); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

// func TestIntegrationKeycloak(t *testing.T) {
// 	ns := cubeTesting.ContainerNS(t.Name())
// 	if testClean(t, func() {
// 		ns.CleanupContainers()
// 		os.RemoveAll(path.Dir(mysqlSockFile))
// 		os.RemoveAll(path.Dir(k3sRegistriesFile))
// 		os.RemoveAll(path.Dir(keycloakSamlMetadataFile))
// 		os.RemoveAll(rancherWorkDir)
// 		os.RemoveAll(certsDir)
// 		os.Remove(terraformStateFile)

// 		resetOpts.hard = true
// 		resetK3s()
// 		resetHost()
// 	}) {
// 		return
// 	}

// 	localIP, err := getIfaceIP("eth0")
// 	if err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := cubeSettings.LoadMap(
// 		map[string]string{
// 			"cubesys.role":       "control",
// 			"cubesys.management": "eth0",
// 			"net.if.addr.eth0":   localIP,
// 			"net.hostname":       "CENTOS8-JAIL",
// 		},
// 	); err != nil {
// 		t.Fatal(err)
// 	}

// 	if _, err := runDockerRegistryContainer(ns); err != nil {
// 		t.Fatal(err)
// 	}

// 	if _, err := ns.RunEtcdContainer(); err != nil {
// 		t.Fatal(err)
// 	}

// 	if _, err := runMysqlContainer(ns, ""); err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := genSelfSignCerts(); err != nil {
// 		t.Fatal(err)
// 	}

// 	// Ignore error
// 	if err := terraformInitBackend(); err != nil {
// 		t.Log(err)
// 	}

// 	if err := commitHost(); err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := commitK3s(); err != nil {
// 		t.Fatal(err)
// 	}

// 	// Create a service to simulate haproxy to forward traffic to ingress
// 	// if err := createHAProxyToIngressService(cubeSettings.GetControllerIp()); err != nil {
// 	// 	t.Fatal(err)
// 	// }

// 	if err := commitMongodb(); err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := commitRedis(); err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := commitKeycloak(); err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := commitTyk(); err != nil {
// 		t.Fatal(err)
// 	}

// 	if err := commitRancher(); err != nil {
// 		t.Fatal(err)
// 	}
// }

// make test RUN=TestIntegrationHostNet TAGS=itest CLEANUP=false
func TestIntegrationHostNet(t *testing.T) {
	if testClean(t, func() {
		cubeTesting.CleanupContainers()
		util.ExecCmd("k3s-uninstall.sh")
		os.RemoveAll("/root/.ssh/")
		os.RemoveAll(path.Dir(mysqlSockFile))
	}) {
		return
	}

	_, err := runMysqlContainer(cubeTesting.ContainerNS(""), "")
	if err != nil {
		t.Fatal(err)
	}

	cc1, err := cubeTesting.RunCubeContainerHostNet("control-converged", nil)
	if err != nil {
		t.Fatal(err)
	}

	if _, outErr, err := cc1.Exec(nil, "cubectl", "config", "commit", "--debug",
		"all",
	); err != nil {
		t.Fatal(outErr, err)
	}

	if err := util.Retry(
		func() error {
			if _, _, err := cc1.Exec(nil, "cubectl", "config", "check", "--debug",
				"all",
			); err != nil {
				return err
			}

			return nil
		},
		30,
	); err != nil {
		t.Fatal(err)
	}
}

// make test RUN=TestIntegrationAll/3cc/Main TAGS=itest CLEANUP=false
func TestIntegrationAll(t *testing.T) {
	tmpDir := "/tmp/" + t.Name()
	if testClean(t, func() {
		cubeTesting.CleanupContainers()
		util.ExecCmd("k3s-uninstall.sh")
		os.RemoveAll("/root/.ssh/")
		os.RemoveAll(path.Dir(mysqlSockFile))
		os.RemoveAll(tmpDir)
	}) {
		return
	}

	cc1Name := "cc-1"
	cc2Name := "cc-2"
	cc3Name := "cc-3"
	cc1Ip := "10.188.10.11"
	cc2Ip := "10.188.10.21"
	cc3Ip := "10.188.10.31"

	ctrlVip := "10.188.10.1"
	ctrlHost := "ctrl-host"

	gwIp, err := getIfaceIP("cni-podman0")
	if err != nil {
		t.Fatal(err)
	}

	settingsHA := []string{
		"cubesys.ha=true",
		"cubesys.seed=secret",
		"cubesys.control.vip=" + ctrlVip,
		"cubesys.controller=" + ctrlHost,
		"cubesys.control.hosts=" + cc1Name + "," + cc2Name + "," + cc3Name,
		"cubesys.control.addrs=" + cc1Ip + "," + cc2Ip + "," + cc3Ip,
	}

	var ctrlIp string
	var wg sync.WaitGroup

	runSetup := func(c *cubeTesting.Container) {
		defer wg.Done()

		if _, outErr, err := c.Exec(nil, "iptables", "-t", "nat", "-A", "PREROUTING",
			"-p", "tcp", "-d", ctrlIp, "--dport", "3306",
			"-j", "DNAT", "--to-destination", gwIp+":3306",
		); err != nil {
			t.Fatal(outErr, err)
		}

		if _, outErr, err := c.Exec(nil, "cubectl", "config", "commit", "--debug",
			"all",
		); err != nil {
			t.Fatal(outErr, err)
		}

		// Test config checks
		if err := util.Retry(
			func() error {
				if _, _, err := c.Exec(nil, "cubectl", "config", "check", "--debug",
					"all",
				); err != nil {
					return err
				}

				return nil
			},
			30,
		); err != nil {
			t.Fatal(err)
		}
	}

	runReset := func(c *cubeTesting.Container) {
		defer wg.Done()

		if _, outErr, err := c.Exec(nil, "cubectl", "config", "reset", "--debug",
			"all",
		); err != nil {
			t.Fatal(outErr, err)
		}

		c.Stop()
		c.Start()
	}

	migrateList := []string{
		"/var/www/certs",
		"/var/lib/terraform/terraform.tfstate",

		// "/etc/rancher/k3s",
		// "/var/lib/rancher/k3s",
		// "/var/lib/kubelet",
		// "/usr/local/bin/k3s",
		// "/usr/local/bin/k3s-killall.sh",
		// "/usr/local/bin/k3s-uninstall.sh",
		// "/etc/systemd/system/k3s.service",
		// "/etc/systemd/system/k3s.service.env",
		// "/run/k3s",
		// "/run/flannel",
		// "/var/lib/rancher/k3s/server/db/snapshots/",
	}

	runUpgrade := func(cOld, cNew *cubeTesting.Container) {
		if _, _, err := cNew.Exec(nil, "touch", migrationMarker); err != nil {
			t.Fatal(err)
		}

		cTmp := tmpDir + "/" + cOld.Hostname
		// Migrate data from old to new node here
		for _, f := range migrateList {
			os.MkdirAll(path.Dir(cTmp+f), 0755)
			cOld.CopyFrom(nil, f, path.Dir(cTmp+f))

			cNew.Exec(nil, "mkdir", "-p", path.Dir(f))
			cNew.CopyTo(nil, cTmp+f, path.Dir(f))
		}

		// Migrate /var/lib/rancher/k3s
		volTmpl := `{{range .Mounts}}{{if eq .Destination "/var/lib/rancher"}}{{.Source}}{{end}}{{end}}`
		k3sVolumeOld := cOld.Inspect(volTmpl)
		k3sVolumeNew := cNew.Inspect(volTmpl)

		// if _, outErr, err := util.ExecCmd("cp", "-a", k3sVolumeOld+"/k3s", k3sVolumeNew); err != nil {
		// 	t.Fatal(err, outErr)
		// }
		if _, outErr, err := util.ExecCmd("rsync", "-aX", k3sVolumeOld+"/k3s", k3sVolumeNew); err != nil {
			t.Fatal(err, outErr)
		}
		// if _, outErr, err := util.ExecShf("(cd %s && find ./k3s -depth -print | cpio -pvumd %s)", k3sVolumeOld, k3sVolumeNew); err != nil {
		// 	t.Fatal(err, outErr)
		// }

		runSetup(cNew)
	}

	downloadLatestK3s := func() error {
		if _, _, err := util.ExecCmd("curl", "-sL", "https://github.com/k3s-io/k3s/releases/download/v1.23.6%2Bk3s1/k3s", "-o", "/opt/k3s/k3s"); err != nil {
			return err
		}

		if _, _, err := util.ExecCmd("chmod", "+x", "/opt/k3s/k3s"); err != nil {
			return err
		}

		return nil
	}

	t.Run("1cc", func(t *testing.T) {
		_, err := runMysqlContainer(cubeTesting.ContainerNS(""), "")
		if err != nil {
			t.Fatal(err)
		}

		cc1, err := cubeTesting.RunCubeContainer(cc1Name, cc1Ip, "control-converged", nil)
		if err != nil {
			t.Fatal(err)
		}

		ctrlIp = cc1.IP

		wg.Add(1)
		go runSetup(cc1)
		wg.Wait()

		t.Run("Main", func(t *testing.T) {
		})

		t.Run("Upgrade", func(t *testing.T) {
			// if _, _, err := cc1.Exec(nil, "k3s", "etcd-snapshot"); err != nil {
			// 	t.Fatal(err)
			// }
			cc1.Stop()

			if err := downloadLatestK3s(); err != nil {
				t.Fatal(err)
			}

			cc1New, err := cubeTesting.RunCubeContainer(cc1Name, cc1Ip, "control-converged", nil)
			if err != nil {
				t.Fatal(err)
			}

			wg.Add(1)
			go runUpgrade(cc1, cc1New)
			wg.Wait()
		})
	})

	t.Run("3cc", func(t *testing.T) {
		_, err := runMysqlContainer(cubeTesting.ContainerNS(""), "")
		if err != nil {
			t.Fatal(err)
		}

		// Generate ssh keys for public key auth
		// Mounted to all cube containers
		if err := genSshKeys(); err != nil {
			t.Fatal(err)
		}

		cc1, err := cubeTesting.RunCubeContainer(cc1Name, cc1Ip, "control-converged", settingsHA)
		if err != nil {
			t.Fatal(err)
		}

		cc2, err := cubeTesting.RunCubeContainer(cc2Name, cc2Ip, "control-converged", settingsHA)
		if err != nil {
			t.Fatal(err)
		}

		cc3, err := cubeTesting.RunCubeContainer(cc3Name, cc3Ip, "control-converged", settingsHA)
		if err != nil {
			t.Fatal(err)
		}

		// Add VIP on controller 1
		if _, outErr, err := cc1.Exec(nil, "ip", "addr", "add", ctrlVip+"/16", "dev", "eth0"); err != nil {
			t.Fatal(outErr, err)
		}

		ctrlIp = ctrlVip + "/24"

		wg.Add(1)
		go runSetup(cc1)
		wg.Wait()

		wg.Add(2)
		go runSetup(cc2)
		go runSetup(cc3)
		wg.Wait()

		t.Run("Main", func(t *testing.T) {
		})

		t.Run("ControlNodeRejoin", func(t *testing.T) {
			// Failed control1
			cc1.Remove()

			// Add VIP on control2
			if _, outErr, err := cc2.Exec(nil, "ip", "addr", "add", ctrlVip+"/16", "dev", "eth0"); err != nil {
				t.Fatal(outErr, err)
			}

			// New created control1
			cc1, err = cubeTesting.RunCubeContainer(cc1Name, cc1Ip, "control-converged", settingsHA)
			if err != nil {
				t.Fatal(err)
			}
			if _, outErr, err := cc1.Exec(nil, "touch", rejoinMarker); err != nil {
				t.Fatal(outErr, err)
			}

			wg.Add(1)
			go runSetup(cc1)
			wg.Wait()

		})

		t.Run("IPChanges", func(t *testing.T) {
			wg.Add(3)
			go runReset(cc1)
			go runReset(cc2)
			go runReset(cc3)
			wg.Wait()

			cc1.IP = "10.188.10.111"
			cc2.IP = "10.188.10.121"
			cc3.IP = "10.188.10.131"
			ctrlVip := "10.188.10.2"

			updatedSettings := map[string]string{
				"cubesys.control.vip":   ctrlVip,
				"cubesys.control.addrs": cc1.IP + "," + cc2.IP + "," + cc3.IP,
			}

			for _, c := range []*cubeTesting.Container{cc1, cc2, cc3} {
				updatedSettings["net.if.addr.eth0"] = c.IP
				if err := c.UpdateSettings(updatedSettings); err != nil {
					t.Fatal(err)
				}
				if _, outErr, err := c.Exec(nil, "ifconfig", "eth0", c.IP+"/16"); err != nil {
					t.Fatal(outErr, err)
				}
				if _, outErr, err := c.Exec(nil, "ip", "route", "add", "default", "via", "10.188.0.1"); err != nil {
					t.Fatal(outErr, err)
				}
			}

			// Add VIP on controller 1
			if _, outErr, err := cc1.Exec(nil, "ip", "addr", "add", ctrlVip+"/16", "dev", "eth0"); err != nil {
				t.Fatal(outErr, err)
			}

			wg.Add(1)
			go runSetup(cc1)
			wg.Wait()

			wg.Add(2)
			go runSetup(cc2)
			go runSetup(cc3)
			wg.Wait()
		})

		t.Run("Upgrade", func(t *testing.T) {
			if _, _, err := cc1.Exec(nil, "k3s", "etcd-snapshot"); err != nil {
				t.Fatal(err)
			}

			if err := downloadLatestK3s(); err != nil {
				t.Fatal(err)
			}

			for _, c := range []*cubeTesting.Container{cc1, cc2, cc3} {
				c.Stop()

				cNew, err := cubeTesting.RunCubeContainer(c.Hostname, c.IP, "control-converged", settingsHA)
				if err != nil {
					t.Fatal(err)
				}

				if c == cc1 {
					// Add VIP on controller 1
					if _, outErr, err := cNew.Exec(nil, "ip", "addr", "add", ctrlVip+"/16", "dev", "eth0"); err != nil {
						t.Fatal(outErr, err)
					}
				}

				wg.Add(1)
				go runUpgrade(c, cNew)
				wg.Wait()
			}
		})
	})
}
