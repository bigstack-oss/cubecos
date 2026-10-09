package config

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/pkg/errors"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
	cubeTesting "cubectl/util/testing"
)

func TestConfigClusterHA(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	if testClean(t, func() {
		ns.CleanupContainers()
		os.RemoveAll("/root/.ssh/")
	}) {
		return
	}

	if err := genSshKeys(); err != nil {
		t.Fatal(err)
	}

	control1Name := "control-1"
	control2Name := "control-2"
	control3Name := "control-3"
	controlVip := "10.188.5.1"
	control1Ip := "10.188.5.11"
	control2Ip := "10.188.5.21"
	control3Ip := "10.188.5.31"

	settingsHA := []string{
		"cubesys.ha=true",
		"cubesys.control.vip=" + controlVip,
		"cubesys.control.hosts=" + control1Name + "," + control2Name + "," + control3Name,
		"cubesys.control.addrs=" + control1Ip + "," + control2Ip + "," + control3Ip,
	}

	control1, err := ns.RunCubeContainer(control1Name, control1Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	// Add VIP on controller 1
	if _, outErr, err := control1.Exec(nil, "ip", "addr", "add", controlVip+"/16", "dev", "eth0"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control1.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	control2, err := ns.RunCubeContainer(control2Name, control2Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control2.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	control3, err := ns.RunCubeContainer(control3Name, control3Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control3.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	out1, _, err := control1.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}
	out2, _, err := control2.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}
	out3, _, err := control3.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}

	assert.JSONEq(t, out1, out2)
	assert.JSONEq(t, out1, out3)

	clusterViper := viper.New()
	clusterViper.SetConfigType("json")
	if err := clusterViper.ReadConfig(bytes.NewBuffer([]byte(out1))); err != nil {
		t.Fatal(err)
	} else {
		//t.Log(viper)
		assert.Equal(t, control1Ip, clusterViper.GetString(control1Name+".ip.management"))
		assert.Equal(t, control2Ip, clusterViper.GetString(control2Name+".ip.management"))
		assert.Equal(t, control3Ip, clusterViper.GetString(control3Name+".ip.management"))
	}

	// Reset cluster
	if _, outErr, err := control1.Exec(nil, "cubectl", "config", "reset", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control2.Exec(nil, "cubectl", "config", "reset", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control3.Exec(nil, "cubectl", "config", "reset", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	// Commit cluster after reset
	if _, outErr, err := control1.Exec(nil, "cubectl", "config", "commit", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control2.Exec(nil, "cubectl", "config", "commit", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control3.Exec(nil, "cubectl", "config", "commit", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	// Test cluster settings
	out1, _, err = control1.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}
	out2, _, err = control2.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}
	out3, _, err = control3.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}

	assert.JSONEq(t, out1, out2)
	assert.JSONEq(t, out1, out3)

	clusterViper = viper.New()
	clusterViper.SetConfigType("json")
	if err := clusterViper.ReadConfig(bytes.NewBuffer([]byte(out1))); err != nil {
		t.Fatal(err)
	} else {
		//t.Log(viper)
		assert.Equal(t, control1Ip, clusterViper.GetString(control1Name+".ip.management"))
		assert.Equal(t, control2Ip, clusterViper.GetString(control2Name+".ip.management"))
		assert.Equal(t, control3Ip, clusterViper.GetString(control3Name+".ip.management"))
	}

	// Test master controller rejoin cluster
	control1.Stop()
	control1.Remove()

	// Add VIP on controller 3
	if _, outErr, err := control3.Exec(nil, "ip", "addr", "add", controlVip+"/16", "dev", "eth0"); err != nil {
		t.Fatal(outErr, err)
	}

	control1, err = ns.RunCubeContainer(control1Name, control1Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control1.Exec(nil, "touch", rejoinMarker); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control1.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	out1, _, err = control1.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}

	viperJson1 := viper.New()
	viperJson1.SetConfigType("json")
	if err := viperJson1.ReadConfig(bytes.NewBuffer([]byte(out1))); err != nil {
		t.Fatal(err)
	} else {
		assert.Equal(t, control1Ip, viperJson1.GetString(control1Name+".ip.management"))
		assert.Equal(t, control2Ip, viperJson1.GetString(control2Name+".ip.management"))
		assert.Equal(t, control3Ip, viperJson1.GetString(control3Name+".ip.management"))
	}

	// Test non-master controller rejoin cluster
	control2.Stop()
	control2.Remove()

	control2, err = ns.RunCubeContainer(control2Name, control2Ip, "control", settingsHA)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control2.Exec(nil, "touch", rejoinMarker); err != nil {
		t.Fatal(outErr, err)
	}
	if _, outErr, err := control2.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	out2, _, err = control2.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}

	viperJson2 := viper.New()
	viperJson2.SetConfigType("json")
	if err := viperJson2.ReadConfig(bytes.NewBuffer([]byte(out2))); err != nil {
		t.Fatal(err)
	} else {
		assert.Equal(t, control1Ip, viperJson2.GetString(control1Name+".ip.management"))
		assert.Equal(t, control2Ip, viperJson2.GetString(control2Name+".ip.management"))
		assert.Equal(t, control3Ip, viperJson2.GetString(control3Name+".ip.management"))
	}
}

func TestConfigClusterSingleController(t *testing.T) {
	ns := cubeTesting.ContainerNS(t.Name())
	if testClean(t, func() {
		ns.CleanupContainers()
		os.RemoveAll("/root/.ssh/")
	}) {
		return
	}

	if err := genSshKeys(); err != nil {
		t.Fatal(err)
	}

	control1Name := "control-1"
	compute1Name := "compute-1"
	storage1Name := "storage-1"
	control1Ip := "10.188.5.111"
	compute1Ip := "10.188.5.121"
	storage1Ip := "10.188.5.131"

	control1, err := ns.RunCubeContainer(control1Name, control1Ip, "control", nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := control1.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	compute1, err := ns.RunCubeContainer(compute1Name, compute1Ip, "compute", []string{"cubesys.controller.ip=" + control1Ip})
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := compute1.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	storage1, err := ns.RunCubeContainer(storage1Name, storage1Ip, "stroage", []string{"cubesys.controller.ip=" + control1Ip})
	if err != nil {
		t.Fatal(err)
	}
	if _, outErr, err := storage1.Exec(nil, "cubectl", "config", "commit", "-d", "cluster"); err != nil {
		t.Fatal(outErr, err)
	}

	out1, _, err := control1.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}
	out2, _, err := compute1.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}
	out3, _, err := storage1.Exec(nil, "cat", util.ClusterSettingsFile)
	if err != nil {
		t.Fatal(err)
	}

	assert.JSONEq(t, out1, out2)
	assert.JSONEq(t, out1, out3)

	viper := viper.New()
	viper.SetConfigType("json")
	if err := viper.ReadConfig(bytes.NewBuffer([]byte(out1))); err != nil {
		t.Fatal(err)
	} else {
		//t.Log(viper)
		assert.Equal(t, control1Ip, viper.GetString(control1Name+".ip.management"))
		assert.Equal(t, compute1Ip, viper.GetString(compute1Name+".ip.management"))
		assert.Equal(t, storage1Ip, viper.GetString(storage1Name+".ip.management"))
	}
}

// The Keycloak SAML clients pin the cluster certificate, so gencerts has to re-apply
// them with the same controller value the shell paths use, and the ceph dashboard SP
// has to get the new pair before its Keycloak client does (#1954).
func TestReapplySamlClients(t *testing.T) {
	nonHA := map[string]string{
		"cubesys.role":       "control-converged",
		"cubesys.ha":         "false",
		"cubesys.management": "eth0",
		"net.if.addr.eth0":   "192.0.2.10",
	}
	apply := func(mod, ip string) string {
		return "apply " + mod + " cube_controller=" + ip + " " + terraformVarFileKeycloakAdminPassword
	}

	tests := []struct {
		name       string
		settings   map[string]string
		ssoEnabled bool
		ssoErr     string // "status" or "setup"
		failMod    string
		expect     []string
		errHas     []string
		errHasNot  []string
	}{
		{
			name:       "non-HA updates the dashboard SP before its client",
			settings:   nonHA,
			ssoEnabled: true,
			expect: []string{
				apply("keycloak_api", "192.0.2.10"),
				"status",
				"setup 192.0.2.10",
				apply("keycloak_ceph_dashboard", "192.0.2.10"),
			},
		},
		{
			name: "HA uses the VIP",
			settings: map[string]string{
				"cubesys.role":        "control",
				"cubesys.ha":          "true",
				"cubesys.control.vip": "192.0.2.11",
			},
			ssoEnabled: true,
			expect: []string{
				apply("keycloak_api", "192.0.2.11"),
				"status",
				"setup 192.0.2.11",
				apply("keycloak_ceph_dashboard", "192.0.2.11"),
			},
		},
		{
			name:     "dashboard SSO off leaves its client alone",
			settings: nonHA,
			expect: []string{
				apply("keycloak_api", "192.0.2.10"),
				"status",
			},
		},
		{
			name:       "a failed SP update skips the dashboard client and fails the command",
			settings:   nonHA,
			ssoEnabled: true,
			ssoErr:     "setup",
			expect: []string{
				apply("keycloak_api", "192.0.2.10"),
				"status",
				"setup 192.0.2.10",
			},
			errHas:    []string{"sso setup saml2 https://192.0.2.10:7443", "module.keycloak_ceph_dashboard"},
			errHasNot: []string{"module.keycloak_api"},
		},
		{
			name:     "an unreadable SSO status skips the dashboard client and fails the command",
			settings: nonHA,
			ssoErr:   "status",
			expect: []string{
				apply("keycloak_api", "192.0.2.10"),
				"status",
			},
			errHas: []string{"sso setup saml2", "module.keycloak_ceph_dashboard"},
		},
		{
			name:       "a failed api client still lets the dashboard through",
			settings:   nonHA,
			ssoEnabled: true,
			failMod:    "keycloak_api",
			expect: []string{
				apply("keycloak_api", "192.0.2.10"),
				"status",
				"setup 192.0.2.10",
				apply("keycloak_ceph_dashboard", "192.0.2.10"),
			},
			errHas:    []string{"module.keycloak_api -var cube_controller=192.0.2.10"},
			errHasNot: []string{"keycloak_ceph_dashboard", "sso setup"},
		},
	}

	// LoadMap replaces the package-global settings; put back what was there so
	// other tests do not depend on running before or after this one.
	prev := map[string]string{}
	for _, k := range cubeSettings.V().AllKeys() {
		prev[k] = cubeSettings.V().GetString(k)
	}
	origApply, origEnabled, origSetup := terraformApply, cephDashboardSsoEnabled, cephDashboardSsoSetup
	t.Cleanup(func() {
		terraformApply, cephDashboardSsoEnabled, cephDashboardSsoSetup = origApply, origEnabled, origSetup
		cubeSettings.LoadMap(prev)
	})

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if err := cubeSettings.LoadMap(test.settings); err != nil {
				t.Fatal(err)
			}

			var calls []string
			terraformApply = func(cmd string, mod string, vars []string, varFiles []string) error {
				calls = append(calls, cmd+" "+mod+" "+strings.Join(vars, " ")+" "+strings.Join(varFiles, " "))
				if mod == test.failMod {
					return errors.New("terraform init failed")
				}
				return nil
			}
			cephDashboardSsoEnabled = func() (bool, error) {
				calls = append(calls, "status")
				if test.ssoErr == "status" {
					return false, errors.New("ceph unreachable")
				}
				return test.ssoEnabled, nil
			}
			cephDashboardSsoSetup = func(ip string) error {
				calls = append(calls, "setup "+ip)
				if test.ssoErr == "setup" {
					return errors.New("mgr unreachable")
				}
				return nil
			}

			err := reapplySamlClients()
			assert.Equal(t, test.expect, calls)

			if len(test.errHas) == 0 {
				assert.NoError(t, err)
				return
			}
			if assert.Error(t, err) {
				for _, want := range test.errHas {
					assert.Contains(t, err.Error(), want)
				}
				for _, unwanted := range test.errHasNot {
					assert.NotContains(t, err.Error(), unwanted)
				}
			}
		})
	}
}

func TestCephDashboardSsoSetupArgs(t *testing.T) {
	// The same arguments ceph_dashboard_idp_config (sdk_ceph.sh) sets the SP up with.
	assert.Equal(t, []string{
		"ceph", "dashboard", "sso", "setup", "saml2",
		"https://192.0.2.10:7443",
		"/etc/keycloak/saml-metadata.xml",
		"username",
		"https://192.0.2.10:10443/auth/realms/master",
		"/var/www/certs/server.cert", "/var/www/certs/server.key",
	}, cephDashboardSsoSetupArgs("192.0.2.10"))
}
