package config

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	rancherDataDir       = "/opt/rancher/"
	rancherWorkDir       = "/root/.rancher/"
	rancherTokenFile     = rancherWorkDir + "/token"
	rancherCliDataFile   = rancherWorkDir + "/cli2.json"
	rancherTmpDir        = "/tmp/rancher/"
	rancherTmpKubeconfig = rancherTmpDir + "/kubeconfig"
	rancherCliBin        = "/usr/local/bin/rancher"
	rancherNamespace     = "cattle-system"
)

type RancherAddNodeOpts struct {
	all          bool
	etcd         bool
	controlplane bool
	worker       bool
}

type RancherCreateNodeTemplateOpts struct {
	openstackConfig string
}

var (
	rancherToken string

	rancherAddNodeOpts            RancherAddNodeOpts
	rancherCreateNodeTemplateOpts RancherCreateNodeTemplateOpts
)

// k3s kubectl create namespace cattle-system

// openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=ctrl-1'

// k3s kubectl -n cattle-system create secret tls tls-rancher-ingress \
//   --cert=/opt/rancher/cert.pem \
//   --key=/opt/rancher/key.pem

// k3s kubectl -n cattle-system create secret generic tls-ca \
//   --from-file=cacerts.pem=/opt/rancher/cert.pem

// helm template rancher /opt/rancher/rancher-2.4.5.tgz --output-dir . \
//     --namespace cattle-system \
//     --set hostname=ctrl-1 \
//     --set ingress.tls.source=secret \
//     --set privateCA=true \
//     --set useBundledSystemChart=true

// k3s kubectl -n cattle-system apply -R -f ./rancher

// kubectl expose -n cattle-system deployment.apps/rancher --type=NodePort --name=rancher-nodeport  --overrides '{ "apiVersion": "v1","spec":{"ports":[{"port":443,"nodePort":30443}]}}'

// k3s kubectl -n cattle-system rollout status deploy/rancher

// k3s crictl inspecti docker.io/rancher/rancher:v2.4.5

func nodeFilter(hosts []string) []string {
	var compHosts []string
	nodeMap, err := util.LoadClusterSettings()
	if err != nil {
		return []string{}
	} else {
		for _, n := range hosts {
			if (*nodeMap)[n].Role != "compute" {
				zap.L().Warn("Skipped the node that doesn't support kubernetes cluster deployment", zap.String("node", n))
				continue
			}
			compHosts = append(compHosts, n)
		}
	}

	return compHosts
}

func rancherGetToken() (string, error) {
	if rancherToken != "" {
		return rancherToken, nil
	}

	// tokenBytes, err := ioutil.ReadFile(rancherTokenFile)
	// if err != nil {
	// 	return "", err
	// }

	out, _, _ := util.ExecShf(`terraform-cube.sh state pull | jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token'`)
	if out == "" || out == "null\n" {
		return "", fmt.Errorf("Token not created")
	}

	rancherToken = strings.TrimSuffix(out, "\n")

	return rancherToken, nil
}

func rancherCliLogin() error {
	token, err := rancherGetToken()
	if err != nil {
		return errors.WithStack(err)
	}

	if _, outErr, err := util.ExecShf("sudo %s login https://localhost:%d --token=%s --skip-verify <<< 1",
		rancherCliBin, k3sIngressHttpsPort, token,
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	// viperJson := viper.New()
	// viperJson.SetConfigType("json")
	// viperJson.SetConfigFile(rancherCliDataFile)
	// if err := viperJson.ReadInConfig(); err != nil {
	// 	errors.WithStack(err)
	// }
	// viperJson.Set("Servers.rancherDefault.project", "")
	// if err := viperJson.WriteConfig(); err != nil {
	// 	errors.WithStack(err)
	// }

	if _, outErr, err := util.ExecCmd("sed", "-i", `s/"project":"[^"]*"/"project":""/g`, rancherCliDataFile); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

func rancherReq(method string, resource string, data string) (map[string]interface{}, error) {
	token, err := rancherGetToken()
	if err != nil {
		return nil, errors.WithStack(err)
	}

	url := fmt.Sprintf("https://%s:%d%s", cubeSettings.GetControllerIp(), k3sIngressHttpsPort, resource)
	req, err := http.NewRequest(method, url, strings.NewReader(data))
	if err != nil {
		return nil, errors.WithStack(err)
	}

	req.Header.Add("Accept", "application/json")
	req.Header.Add("Content-Type", "application/json")
	req.AddCookie(&http.Cookie{Name: "R_SESS", Value: token})
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	defer resp.Body.Close()

	//zap.S().Debug(resp)

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	var result map[string]interface{}
	if len(bodyBytes) == 0 {
		result = nil
	} else {
		zap.L().Debug("Received response", zap.Int("StatusCode", resp.StatusCode), zap.String("body", string(bodyBytes)))

		if err := json.Unmarshal(bodyBytes, &result); err != nil {
			return nil, errors.WithStack(err)
		}
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, errors.WithStack(fmt.Errorf("Failed to request %s", resource))
	}

	//zap.L().Debug("Rancher config request successfully", zap.String("resource", resource), zap.String("data", data), zap.Any("result", result))
	zap.L().Debug("Rancher config request successfully", zap.String("resource", resource), zap.String("data", data))

	return result, nil
}

func rancherConfigClusterNodeDrivers() error {
	enabledTypeDrivers := map[string]map[string]bool{
		"kontainerDrivers": {},
		"nodeDrivers":      {
			// "openstack": true,
		},
	}

	var nodeDrvFound bool
	for key, val := range enabledTypeDrivers {
		result, err := rancherReq("GET",
			"/v3/"+key,
			``,
		)
		if err != nil {
			return errors.WithStack(err)
		}

		for _, data := range result["data"].([]interface{}) {
			id := data.(map[string]interface{})["id"].(string)

			// Found if default node driver was created
			if key == "nodeDrivers" {
				name := data.(map[string]interface{})["name"].(string)
				if name == "cube" {
					nodeDrvFound = true
					// Do not take action for default node driver
					continue
				}
			}

			var action string
			if _, ok := val[id]; ok {
				action = "activate"
			} else {
				action = "deactivate"
			}

			if _, err := rancherReq("POST",
				"/v3/"+key+"/"+id+"?action="+action,
				``,
			); err != nil {
				return errors.WithStack(err)
			}
			zap.L().Info("Rancher driver configured", zap.Any("id", id), zap.Any("action", action))
		}
	}

	if nodeDrvFound {
		zap.L().Info("Rancher default node driver found")
	} else {
		driverDataFmt := `
{
	"active": true,
	"builtin": false,
	"name": "cube",
	"url": "http://%s:8080/static/nodedrivers/docker-machine-driver-cube"
}
`

		if _, err := rancherReq("POST",
			"/v3/nodedrivers",
			fmt.Sprintf(driverDataFmt, cubeSettings.GetControllerIp()),
		); err != nil {
			return errors.WithStack(err)
		}

		zap.L().Info("Rancher default node driver created", zap.String("name", "cube"))
	}

	return nil
}

func rancherConfigInit() error {
	// if err := rancherReq("PUT",
	// 	"/v3/settings/first-login",
	// 	`{"value":"false"}`,
	// ); err != nil {
	// 	return errors.WithStack(err)
	// }

	// Change password so that password change prompt won't show up
	// if _, err := rancherReq("POST",
	// 	"/v3/users?action=changepassword",
	// 	`{"currentPassword":"admin","newPassword":"admin"}`,
	// ); err != nil {
	// 	return errors.WithStack(err)
	// }

	if err := rancherConfigClusterNodeDrivers(); err != nil {
		return errors.WithStack(err)
	}

	// Enable unsupported storage drivers
	if _, err := rancherReq("PUT",
		"/v3/features/unsupported-storage-drivers",
		`{"value":"true"}`,
	); err != nil {
		return errors.WithStack(err)
	}

	if _, err := rancherReq("PUT",
		"/v3/features/continuous-delivery",
		`{"value":"false"}`,
	); err != nil {
		return errors.WithStack(err)
	}

	if _, err := rancherReq("PUT",
		"/v3/features/harvester",
		`{"value":"false"}`,
	); err != nil {
		return errors.WithStack(err)
	}

	if _, err := rancherReq("PUT",
		"/v3/features/legacy",
		`{"value":"false"}`,
	); err != nil {
		return errors.WithStack(err)
	}

	// Disable auto-update rke-metadata-config
	// if _, err := rancherReq("PUT",
	// 	"/v3/settings/rke-metadata-config",
	// 	`{"value":"{\"refresh-interval-minutes\":\"0\",\"url\":\"https://releases.rancher.com/kontainer-driver-metadata/release-v2.4/data.json\"}"}`,
	// ); err != nil {
	// 	return errors.WithStack(err)
	// }

	// UI lable
	if _, err := rancherReq("PUT",
		"/v3/settings/ui-pl",
		`{"value":"Kubernetes"}`,
	); err != nil {
		return errors.WithStack(err)
	}

	// Issues report address
	if _, err := rancherReq("PUT",
		"/v3/settings/ui-issues",
		`{"value":"https://www.bigstack.co/contact/"}`,
	); err != nil {
		return errors.WithStack(err)
	}

	// Hide local cluster
	// if _, err := rancherReq("PUT",
	// 	"/v3/settings/hide-local-cluster",
	// 	`{"value":"true"}`,
	// ); err != nil {
	// 	return errors.WithStack(err)
	// }

	// UI k8s version support range
	// Will be reloaded by rancher
	// if err := rancherReq("PUT",
	// 	"/v3/settings/ui-k8s-supported-versions-range",
	// 	`{"value":">=v1.18.x <=v1.18.x"}`,
	// ); err != nil {
	// 	return errors.WithStack(err)
	// }

	// k8s version support
	// Will be reloaded by rancher
	// if result, err := rancherReq("GET",
	// 	"/v3/settings/k8s-version",
	// 	``,
	// ); err != nil {
	// 	return errors.WithStack(err)
	// } else {
	// 	version := result["value"].(string)
	// 	zap.L().Debug("k8s version", zap.String("version", version))

	// 	if _, err := rancherReq("PUT",
	// 		"/v3/settings/k8s-version-to-images",
	// 		`{"value":"{\"`+version+`\":null}"}`,
	// 	); err != nil {
	// 		return errors.WithStack(err)
	// 	}
	// }

	return nil
}

func rancherCreateToken() error {
	url := "https://localhost:" + strconv.Itoa(k3sIngressHttpsPort)

	// Use basic auth to get a temp token
	var tokenTmp string
	if req, err := http.NewRequest("POST",
		url+"/v3-public/localProviders/local?action=login",
		strings.NewReader(`{"username":"admin","password":"admin","responseType":"cookie"}`),
	); err != nil {
		return errors.WithStack(err)
	} else {
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return errors.WithStack(err)
		}
		defer resp.Body.Close()

		zap.S().Debug(resp.Cookies())
		for _, cookie := range resp.Cookies() {
			if cookie.Name == "R_SESS" {
				tokenTmp = cookie.Value
			}
		}

		if tokenTmp == "" {
			return errors.WithStack(fmt.Errorf("No token found"))
		}
		zap.L().Debug("Auth token", zap.String("R_SESS", tokenTmp))
	}

	// Create a permanent token and save to file
	if req, err := http.NewRequest("POST",
		url+"/v3/token",
		strings.NewReader(`{"current":false,"enabled":true,"expired":false,"isDerived":false,"ttl":0,"type":"token","description":"cube-token"}`),
	); err != nil {
		return errors.WithStack(err)
	} else {
		req.AddCookie(&http.Cookie{Name: "R_SESS", Value: tokenTmp})
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return errors.WithStack(err)
		}
		defer resp.Body.Close()

		zap.S().Debug(resp)
		if resp.StatusCode != 201 {
			return errors.WithStack(fmt.Errorf("Failed to create token"))
		}

		bodyBytes, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			return errors.WithStack(err)
		}
		zap.L().Debug("Received response", zap.String("body", string(bodyBytes)))

		var result map[string]interface{}
		if err := json.Unmarshal(bodyBytes, &result); err != nil {
			return errors.WithStack(err)
		}

		token := result["token"].(string)
		zap.L().Debug("Token", zap.String("token", token))

		if err := ioutil.WriteFile(rancherTokenFile, []byte(token), 0644); err != nil {
			return errors.WithStack(err)
		}

		zap.L().Info("Rancher token created")
	}

	return nil
}

func rancherDeleteToken() error {
	result, err := rancherReq("GET",
		"/v3/tokens",
		``,
	)
	if err != nil {
		return errors.WithStack(err)
	}

	for _, t := range result["data"].([]interface{}) {
		//zap.L().Debug("token data", zap.Any("data", t))

		tokenData := t.(map[string]interface{})
		//if tokenData["description"].(string) == "cube-token" {

		id := tokenData["id"].(string)
		if _, err := rancherReq("DELETE",
			"/v3/tokens/"+id,
			``,
		); err != nil {
			zap.L().Warn("Failed to delete token", zap.String("id", id), zap.Error(err))
		}
		zap.L().Info("Cube token deleted", zap.Any("id", id))

		//}
	}

	return nil
}

/* func commitRancherOld() error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	// Import rancher images on every control nodes
	if _, _, err := util.ExecShf("cat %s | xargs k3s crictl inspecti -q", rancherImagesFile); err == nil {
		zap.L().Debug("Rancher images existed")
	} else {
		zap.L().Info("Rancher images importing...")
		if _, outErr, err := util.ExecSh("find " + rancherImagesDir + ` -type f -exec k3s ctr images import {} \;`); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher images imported")
	}

	// Deploy rancher when cattle-system is not created yet
	if _, _, err := util.ExecCmd(k3sBinPath, "kubectl", "get", "namespace", rancherNamespace); err == nil {
		zap.L().Debug("Rancher namespace existed")

		// sync rancher token and cli data from master controller to every controllers
		if _, _, err := util.ExecCmd("cubectl", "node", "rsync", cubeSettings.GetController()+":"+rancherWorkDir); err != nil {
			return errors.WithStack(err)
		}
		zap.L().Info("Rancher working data synced")
	} else {
		os.MkdirAll(rancherWorkDir, 0755)

		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl", "create", "namespace", rancherNamespace); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher namespace created")
	}

	if _, err := os.Stat(rancherCertFile); os.IsNotExist(err) {
		sansStr := `
[req]
distinguished_name=req
[san]
subjectAltName=DNS:localhost,IP:127.0.0.1` + ",IP:" + cubeSettings.GetControllerIp()

		if err := ioutil.WriteFile(rancherCertSansFile, []byte(sansStr), 0644); err != nil {
			return errors.WithStack(err)
		}

		if _, outErr, err := util.ExecCmd("openssl",
			"req", "-x509", "-newkey", "rsa:2048", "-nodes",
			"-keyout", rancherKeyFile,
			"-out", rancherCertFile,
			"-days", "3650",
			"-subj", "/CN="+cubeSettings.GetController(),
			"-addext", "basicConstraints=CA:TRUE,pathlen:0",
			"-extensions", "san",
			"-config", rancherCertSansFile,
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher self-signed cert genreated")

		// if _, outErr, err := util.ExecShf("openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -extensions san"+
		// 	" -keyout %s"+
		// 	" -out %s"+
		// 	" -subj '%s'"+
		// 	" -config < (echo '%s')",
		// 	rancherKeyFile, rancherCertFile, cubeSettings.GetController(), sansCnf,
		// ); err != nil {
		// 	return errors.Wrap(err, outErr)
		// }

		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
			"-n", rancherNamespace,
			"create", "secret", "tls", "tls-rancher-private",
			"--cert="+rancherCertFile,
			"--key="+rancherKeyFile,
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher secret created", zap.String("name", "tls-rancher-private"))

		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
			"-n", rancherNamespace,
			"create", "secret", "generic", "tls-ca",
			"--from-file=cacerts.pem="+rancherCertFile,
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher secret created", zap.String("name", "tls-ca"))

		// if _, outErr, err := util.ExecCmd(helmBin,
		// 	"template", "rancher", rancherChartFile,
		// 	"--namespace", rancherNamespace,
		// 	"--output-dir", rancherWorkDir,
		// 	//"--set", "hostname="+cubeSettings.GetController(),
		// 	//"--set", "ingress.tls.source=secret",
		// 	"--set", "privateCA=true",
		// 	"--set", "useBundledSystemChart=true",
		// 	"--set", "tls=external",
		// 	"--set", "debug=true",
		// ); err != nil {
		// 	return errors.Wrap(err, outErr)
		// }

		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
			"-n", rancherNamespace,
			"apply", "-R",
			"-f", rancherDataDir+"/templates",
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher deployment applied")

		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
			"-n", rancherNamespace,
			"rollout", "status", "--timeout=3m",
			"deployment.apps/rancher",
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Debug("Rancher deployment rolled out")

		// FIXME: do not apply ingress.yaml
		// if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
		// 	"-n", rancherNamespace,
		// 	"delete",
		// 	"ingress", "rancher",
		// ); err != nil {
		// 	return errors.Wrap(err, outErr)
		// }

		// Use NodePort
		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
			"-n", rancherNamespace,
			"expose", "deployment.apps/rancher",
			"--type=NodePort", "--name=rancher-nodeport",
			"--overrides", `{"apiVersion":"v1","spec":{"ports":[{"port":443,"nodePort":`+strconv.Itoa(rancherPort)+`}]}}`,
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Rancher service exposed", zap.Int("NodePort", rancherPort))

		if err := util.CheckService("localhost", rancherPort, 10); err != nil {
			return errors.WithStack(err)
		}

		// deleted by reset --hard
		if _, err := os.Stat(rancherTokenFile); os.IsNotExist(err) {
			if err := rancherCreateToken(); err != nil {
				return errors.WithStack(err)
			}

			if err := rancherConfigInit(); err != nil {
				return errors.WithStack(err)
			}
		}

		// server-url
		// Always set it because controller ip might changes after reset
		if _, err := rancherReq("PUT",
			"/v3/settings/server-url",
			`{"value":"https://`+cubeSettings.GetControllerIp()+":"+strconv.Itoa(rancherPort)+`"}`,
		); err != nil {
			return errors.WithStack(err)
		}

		if err := rancherCliLogin(); err != nil {
			return errors.WithStack(err)
		}

		// TODO: Check what timing issue causes rancher-agnet use incorrect ca-checksum
		// Run this command to make sure cattle-cluster-agent and cattle-node-agent use the latest ca-checksum for every create clusters
		// if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
		// 	"patch",
		// 	"cluster", "local",
		// 	"-p", `{"status":{"agentImage":"dummy"}}`,
		// 	"--type", "merge",
		// ); err != nil {
		// 	return errors.Wrap(err, outErr)
		// }
		// zap.L().Info("Rancher cluster patched", zap.String("cluster", "local"))
	}

	return nil
} */

func commitRancher() error {
	if cubeSettings.GetRole() == "undef" || cubeSettings.GetRole() == "edge-core" || cubeSettings.GetRole() == "moderator" {
		return nil
	}

	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	if err := k3sCheckReplicas("deployment.apps/rancher", rancherNamespace); err != nil || commitOpts.force || isMigration() {
		if err := k3sCreateNamespace(rancherNamespace); err != nil {
			return errors.WithStack(err)
		}

		if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
			"create", "secret", "generic", "tls-ca",
			"-n", rancherNamespace,
			"--from-file=cacerts.pem="+certFile,
		); err != nil {
			zap.S().Warn(errors.Wrap(err, outErr))
		} else {
			zap.L().Info("Rancher secret created", zap.String("name", "tls-ca"))
		}

		nodeCount, err := k3sGetNodeCounts()
		if err != nil {
			return errors.WithStack(err)
		}

		if err := util.Retry(
			func() error {
				if _, outErr, err := util.ExecShf("helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install rancher %s -n cattle-system --create-namespace -f %s --set replicas=%d",
					rancherDataDir+"/rancher-*.tgz", rancherDataDir+"/chart-values.yaml", nodeCount,
				); err != nil {
					return errors.Wrap(err, outErr)
				}
				zap.L().Info("Rancher release upgraded")

				return nil
			},
			3,
		); err != nil {
			return errors.WithStack(err)
		}

		if err := k3sWatchRollOut("deployment.apps/rancher", rancherNamespace, "3m"); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		// Create token and eanble keycloak auth
		if err := terraformExec("apply", "rancher", "cube_controller="+cubeSettings.GetControllerIp()); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		// Create rancher client on keycloak
		if err := terraformExec("apply", "keycloak_rancher", "cube_controller="+cubeSettings.GetControllerIp()); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		if err := rancherConfigInit(); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}
	}

	// else {
	// 	//sync rancher token and cli data from master controller to every controllers
	// 	if _, _, err := util.ExecCmd("cubectl", "node", "rsync", cubeSettings.GetControllerIp()+":"+rancherWorkDir); err != nil {
	// 		return errors.WithStack(err)
	// 	}
	// 	zap.L().Info("Rancher working data synced")
	// }

	if err := rancherCliLogin(); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func resetRancher() error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	os.RemoveAll(rancherWorkDir)

	if err := terraformExec("destroy", "keycloak_rancher", "cube_controller="+cubeSettings.GetControllerIp()); err != nil {
		zap.S().Warn(errors.WithStack(err))
	}

	if err := terraformExec("destroy", "rancher", "cube_controller="+cubeSettings.GetControllerIp()); err != nil {
		zap.S().Warn(errors.WithStack(err))
	}

	if _, outErr, err := util.ExecCmd("helm",
		"--kubeconfig=/etc/rancher/k3s/k3s.yaml",
		"uninstall",
		"rancher", "-n", rancherNamespace,
	); err != nil {
		zap.S().Warn(errors.Wrap(err, outErr))
	}
	zap.L().Info("Rancher release uninstalled")

	if _, outErr, err := util.ExecCmd(k3sBinPath, "kubectl",
		"delete", "secret", "tls-ca",
		"-n", rancherNamespace,
	); err != nil {
		zap.S().Warn(errors.Wrap(err, outErr))
	}

	if resetOpts.hard {
		if err := k3sDeleteNamespace(rancherNamespace); err != nil {
			zap.S().Warn(errors.WithStack(err))
		}

		// TODO: Remove rancher config in db
	}

	return nil
}

func statusRancher() error {
	if out, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"get", "all", "-n", rancherNamespace,
		"-o", "wide",
	); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		fmt.Println(out)
	}

	return nil
}

func checkRancher() error {
	if err := k3sWatchRollOut("deployment.apps/rancher", rancherNamespace, "1s"); err != nil {
		return errors.WithStack(err)
	}

	nodeCount, err := k3sGetNodeCounts()
	if err != nil {
		return errors.WithStack(err)
	}

	replicaCount, err := k3sGetReadyReplicas("deployment.apps/rancher", rancherNamespace)
	if err != nil {
		return errors.WithStack(err)
	}

	if nodeCount != replicaCount {
		return fmt.Errorf("Control node count: %d doesn't match replica count: %d", nodeCount, replicaCount)
	}

	return nil
}

func repairRancher() error {
	if !cubeSettings.IsRole(util.ROLE_CONTROL) {
		return nil
	}

	// if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
	// 	"rollout", "restart",
	// 	"deployment.apps/rancher", "-n", rancherNamespace,
	// ); err != nil {
	// 	return errors.Wrap(err, outErr)
	// }

	// if _, outErr, err := util.ExecCmd("cubectl",
	// 	"node", "exec", "--role=control",
	// 	"cubectl", "config", "reset",
	// 	"rancher",
	// ); err != nil {
	// 	return errors.Wrap(err, outErr)
	// }

	// if _, outErr, err := util.ExecCmd("cubectl",
	// 	"node", "exec", "--role=control",
	// 	"cubectl", "config", "commit",
	// 	"rancher",
	// ); err != nil {
	// 	return errors.Wrap(err, outErr)
	// }

	if _, outErr, err := util.ExecCmd("/usr/local/bin/k3s", "kubectl",
		"delete", "pods", "--all", "-n", rancherNamespace,
		"--grace-period=0", "--force",
	); err != nil {
		return errors.Wrap(err, outErr)
	}

	if err := k3sWatchRollOut("deployment.apps/rancher", rancherNamespace, "3m"); err != nil {
		return errors.WithStack(err)
	}

	return nil
}

var cmdRancherAddNode = &cobra.Command{
	Use:   "add-node <cluster-name> <node>...",
	Short: "Add node(s) to kubernetes cluster",
	Args:  cobra.MinimumNArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		clusterName := args[0]
		hosts := nodeFilter(args[1:])
		if len(hosts) == 0 {
			return fmt.Errorf("No available nodes")
		}

		// if _, outErr, err := util.ExecShf("sudo %s context switch <<< 1",
		// 	rancherCliBin,
		// ); err != nil {
		// 	return errors.Wrap(err, outErr)
		// }

		var dockerCmd string
		if out, outErr, err := util.ExecCmd("sudo", rancherCliBin, "cluster", "add-node", clusterName,
			"--quiet",
		); err != nil {
			return errors.Wrap(err, outErr)
		} else {
			dockerCmd = strings.TrimSuffix(out, "\n")
		}

		if rancherAddNodeOpts.etcd || rancherAddNodeOpts.all {
			dockerCmd += " --etcd"
		}
		if rancherAddNodeOpts.controlplane || rancherAddNodeOpts.all {
			dockerCmd += " --controlplane"
		}
		if rancherAddNodeOpts.worker || rancherAddNodeOpts.all {
			dockerCmd += " --worker"
		}

		if _, outErr, err := util.ExecCmd("cubectl", "node", "exec",
			"--hosts", strings.Join(hosts, ","),
			dockerCmd,
		); err != nil {
			return errors.Wrap(err, outErr)
		}

		return nil
	},
}

var cmdRancherCleanNode = &cobra.Command{
	Use:   "clean-node <node>...",
	Short: "Cleanup node(s) in kubernetes cluster",
	Args:  cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		// ETCD snapshot on compute nodes
		// /opt/rke/etcd-snapshots/

		hosts := nodeFilter(args)
		if len(hosts) == 0 {
			return fmt.Errorf("No available nodes")
		}

		if _, outErr, err := util.ExecCmd("cubectl", "node", "exec",
			"--parallel",
			"--hosts", strings.Join(hosts, ","),
			rancherDataDir+"/clean-k8s.sh",
		); err != nil {
			return errors.Wrap(err, outErr)
		}

		return nil
	},
}

var cmdRancherCreateCephStorageClass = &cobra.Command{
	Use:   "create-ceph-storageclass",
	Short: "Create a default ceph storage class for a kubernetes cluster",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if !cubeSettings.IsRole(util.ROLE_CONTROL) {
			return fmt.Errorf("Can only be executed on control nodes")
		}

		cluster := args[0]

		var cephStorageClassFmt = `
---
apiVersion: v1
kind: Secret
metadata:
  name: ceph-secret-admin
  namespace: kube-system
data:
  key: %s
type: kubernetes.io/rbd

---
apiVersion: v1
kind: Secret
metadata:
  name: ceph-secret-k8s
  namespace: kube-system
data:
  key: %s
type: kubernetes.io/rbd

---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-default
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/rbd
parameters:
  monitors: %s
  adminId: admin
  adminSecretName: ceph-secret-admin
  adminSecretNamespace: kube-system
  pool: k8s-volumes
  userId: k8s
  userSecretName: ceph-secret-k8s
  userSecretNamespace: kube-system
  fsType: ext4
  imageFormat: "2"
  imageFeatures: "layering"
`

		os.MkdirAll(rancherTmpDir, 0755)
		cephKeyringAdmin, _, err := util.ExecSh(`cat /etc/ceph/ceph.client.admin.keyring | grep key|awk '{print $3}' | base64`)
		if err != nil {
			return errors.WithStack(err)
		}

		cephKeyringK8s, _, err := util.ExecSh(`cat /etc/ceph/ceph.client.k8s.keyring | grep key|awk '{print $3}' | base64`)
		if err != nil {
			return errors.WithStack(err)
		}

		var cephMonitors []string
		if cubeSettings.IsHA() {
			cephMonitors = append(cephMonitors, cubeSettings.GetControlGroupIPs()...)
		} else {
			cephMonitors = []string{cubeSettings.GetControllerIp()}
		}

		for i := range cephMonitors {
			cephMonitors[i] += ":6789"
		}

		cephStorageClassYaml := fmt.Sprintf(cephStorageClassFmt, cephKeyringAdmin, cephKeyringK8s, strings.Join(cephMonitors, ","))
		if err := ioutil.WriteFile(rancherTmpDir+"/ceph-storageclass.yaml", []byte(cephStorageClassYaml), 0644); err != nil {
			return errors.WithStack(err)
		}

		if out, outErr, err := util.ExecCmd("sudo", rancherCliBin, "clusters", "kubeconfig", cluster); err != nil {
			return errors.Wrap(err, outErr)
		} else {
			if err := ioutil.WriteFile(rancherTmpKubeconfig, []byte(out), 0644); err != nil {
				return errors.WithStack(err)
			}
		}

		if _, outErr, err := util.ExecCmd("kubectl",
			"--kubeconfig="+rancherTmpKubeconfig,
			"create", "-f", rancherTmpDir+"/ceph-storageclass.yaml",
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Ceph storage class created")

		return nil
	},
}

var cmdRancherCreateNodeTemplate = &cobra.Command{
	Use:   "create-nodetemplate",
	Short: "Create a default node template",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if !cubeSettings.IsRole(util.ROLE_CONTROL) {
			return fmt.Errorf("Can only be executed on control nodes")
		}

		templateName := args[0]

		var openstackConfig map[string]interface{}
		if err := json.Unmarshal([]byte(rancherCreateNodeTemplateOpts.openstackConfig), &openstackConfig); err != nil {
			return errors.WithStack(err)
		}

		tmplData := map[string]interface{}{
			"name":             templateName,
			"type":             "nodeTemplate",
			"engineInstallURL": "https://get.docker.com",
			"engineInsecureRegistry": []string{
				cubeSettings.GetController() + ":" + strconv.Itoa(dockerRegistryPort),
				cubeSettings.GetControllerIp() + ":" + strconv.Itoa(dockerRegistryPort),
			},
			"engineRegistryMirror": []string{
				"http://" + cubeSettings.GetControllerIp() + ":" + strconv.Itoa(dockerRegistryPort),
			},
			"openstackConfig": openstackConfig,
		}

		data, err := json.Marshal(tmplData)
		if err != nil {
			return errors.WithStack(err)
		}

		//fmt.Println(string(data))
		if _, err := rancherReq("POST",
			"/v3/nodetemplate",
			string(data),
		); err != nil {
			return errors.WithStack(err)
		}

		zap.L().Info("Node template created", zap.String("name", templateName))

		return nil
	},
}

func init() {
	m := NewModule("rancher")
	m.commitFunc = commitRancher
	m.resetFunc = resetRancher
	m.statusFunc = statusRancher
	m.checkFunc = checkRancher
	m.repairFunc = repairRancher

	cobra.EnableCommandSorting = false
	m.AddCustomCommand(cmdRancherAddNode)
	cmdRancherAddNode.Flags().BoolVar(&rancherAddNodeOpts.all, "all", false, "Nodes with all role")
	cmdRancherAddNode.Flags().BoolVar(&rancherAddNodeOpts.etcd, "etcd", false, "Nodes with etcd role")
	cmdRancherAddNode.Flags().BoolVar(&rancherAddNodeOpts.controlplane, "controlplane", false, "Nodes with control plane role")
	cmdRancherAddNode.Flags().BoolVar(&rancherAddNodeOpts.worker, "worker", false, "Nodes with worker role")
	cmdRancherAddNode.Flags().SortFlags = false
	m.AddCustomCommand(cmdRancherCleanNode)
	m.AddCustomCommand(cmdRancherCreateCephStorageClass)
	m.AddCustomCommand(cmdRancherCreateNodeTemplate)
	cmdRancherCreateNodeTemplate.Flags().StringVar(&rancherCreateNodeTemplateOpts.openstackConfig, "openstack-config", "", "Config for OpenStack")

	http.DefaultTransport.(*http.Transport).TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
}
