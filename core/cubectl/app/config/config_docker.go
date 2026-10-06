package config

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path"
	"regexp"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	dockerConfigFile      = "/etc/docker/daemon.json"
	dockerDataDir         = "/opt/docker/"
	dockerRegistryArchive = dockerDataDir + "/registry@2.tar"
	dockerRegistryVolume  = dockerDataDir + "/registry"
	dockerRegistryPort    = 5080
)

func dockerCheckImage(imgsFile string) error {
	file, err := os.Open(imgsFile)
	if err != nil {
		return errors.WithStack(err)
	}
	defer file.Close()

	errCount := 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		if scanner.Text() == "" {
			continue
		}

		re := regexp.MustCompile(`^[a-zA-Z0-9\\-]+\.[a-zA-Z0-9\-\.]+/`)
		imageWithoutRepo := re.ReplaceAllString(scanner.Text(), "")

		pathTag := strings.SplitN(imageWithoutRepo, ":", 2)
		path := pathTag[0]
		var tag string
		if len(pathTag) > 1 {
			tag = pathTag[1]
		} else {
			tag = "latest"
		}

		req, err := http.NewRequest("GET", "http://localhost:"+strconv.Itoa(dockerRegistryPort)+"/v2/"+path+"/manifests/"+tag, nil)
		if err != nil {
			return errors.WithStack(err)
		}

		ok := true
		if resp, err := http.DefaultClient.Do(req); err != nil {
			return errors.WithStack(err)
		} else {
			defer resp.Body.Close()

			if resp.StatusCode != 200 {
				ok = false
				errCount++
			}
		}

		fmt.Print(scanner.Text(), " ")
		if ok {
			fmt.Println("<Y>")
		} else {
			fmt.Println("<N>")
		}
	}

	if errCount > 0 {
		return fmt.Errorf("%d images are not imported", errCount)
	}

	return nil
}

// dockerEnsureConf lists the registry in file's insecure-registries and keeps every other key
// as it is: a site may carry its own, such as a bip and default-address-pools moving docker off
// 172.17.0.0/16. Without the entry, docker 29 pushes to <reg>:5080 over https and fails. It
// reports whether it wrote the file.
func dockerEnsureConf(file string, reg string) (bool, error) {
	entry := fmt.Sprintf("%s:%d", reg, dockerRegistryPort)

	conf := map[string]interface{}{}
	if data, err := os.ReadFile(file); err == nil {
		dec := json.NewDecoder(bytes.NewReader(data))
		dec.UseNumber()
		if err := dec.Decode(&conf); err != nil {
			return false, errors.Wrapf(err, "failed to parse %s", file)
		}
		if conf == nil {
			conf = map[string]interface{}{}
		}
	} else if !os.IsNotExist(err) {
		return false, errors.WithStack(err)
	}

	regs, _ := conf["insecure-registries"].([]interface{})
	for _, r := range regs {
		if r == entry {
			return false, nil
		}
	}
	conf["insecure-registries"] = append(regs, entry)

	out, err := json.MarshalIndent(conf, "", "  ")
	if err != nil {
		return false, errors.WithStack(err)
	}
	if err := os.MkdirAll(path.Dir(file), 0755); err != nil {
		return false, errors.WithStack(err)
	}
	if err := os.WriteFile(file, out, 0644); err != nil {
		return false, errors.WithStack(err)
	}

	return true, nil
}

func commitDocker() error {
	if cubeSettings.GetRole() == "undef" {
		return nil
	}

	// Generate docker config if not existed, or add the registry to a site's own
	_, statErr := os.Stat(dockerConfigFile)
	updated, err := dockerEnsureConf(dockerConfigFile, cubeSettings.GetController())
	if err != nil {
		return errors.WithStack(err)
	}
	switch {
	case !updated:
		zap.L().Debug("Docker config existed")
	case statErr == nil:
		zap.L().Info("Docker config updated with the registry")
	default:
		zap.L().Info("Docker config generated")
	}

	// Start docker daemon
	if _, outErr, err := util.ExecCmd("systemctl", "start", "docker"); err != nil {
		return errors.Wrap(err, outErr)
	}
	zap.L().Info("Docker daemon started")

	// A daemon already running keeps its old insecure-registries until it reloads them
	if updated {
		if _, outErr, err := util.ExecCmd("systemctl", "reload", "docker"); err != nil {
			return errors.Wrap(err, outErr)
		}
	}

	// Run private registry if it's control node
	if cubeSettings.IsRole(util.ROLE_CONTROL) {
		if _, _, err := util.ExecCmd("docker", "inspect", "--format={{.Id}}", "registry"); err == nil {
			zap.L().Debug("Docker registry existed")
		} else {
			if _, outErr, err := util.ExecCmd("docker", "load", "-i", dockerRegistryArchive); err != nil {
				return errors.Wrap(err, outErr)
			}

			if _, outErr, err := util.ExecCmd("docker",
				"run", "-d",
				"-p", strconv.Itoa(dockerRegistryPort)+":5000",
				"-v", dockerRegistryVolume+":/var/lib/registry",
				"--restart", "always",
				"--name", "registry",
				"registry:2",
			); err != nil {
				return errors.Wrap(err, outErr)
			}

			zap.L().Info("Docker registry created")
		}
	}

	return nil
}

func resetDocker() error {
	if cubeSettings.IsRole(util.ROLE_CONTROL) {
		if _, outErr, err := util.ExecCmd("docker", "stop", "registry"); err != nil {
			zap.S().Warn(errors.Wrap(err, outErr))
		}

		if resetOpts.hard {
			if _, outErr, err := util.ExecCmd("docker", "rm", "registry"); err != nil {
				zap.S().Warn(errors.Wrap(err, outErr))
			}
		}
	}

	util.ExecCmd("systemctl", "stop", "docker")
	os.Remove(dockerConfigFile)

	zap.L().Info("Docker daemon stopped")

	return nil
}

func statusDocker() error {
	if out, outErr, err := util.ExecCmd("docker",
		"ps", "--all", "--size",
	); err != nil {
		return errors.Wrap(err, outErr)
	} else {
		fmt.Println(out)
	}

	return nil
}

func repairDocker() error {
	if _, outErr, err := util.ExecCmd("systemctl", "restart", "docker"); err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}

var cmdDockerImportRegistry = &cobra.Command{
	Use:   "import-registry <registry tarbal>",
	Short: "Import registry volume to private registry",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		importArchive := args[0]

		if _, err := os.Stat(dockerRegistryVolume + ".org"); os.IsNotExist(err) {
			if err := os.Rename(dockerRegistryVolume, dockerRegistryVolume+".org"); err != nil {
				return errors.WithStack(err)
			}
		} else {
			os.RemoveAll(dockerRegistryVolume)
		}

		zap.L().Info("Extracting " + importArchive)
		if _, outErr, err := util.ExecCmd("tar", "-C", dockerDataDir, "-xvf", importArchive); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Registry volume extracted")

		zap.L().Info("Syncing registry volume to every control nodes")
		if _, outErr, err := util.ExecCmd("cubectl", "node", "rsync", dockerRegistryVolume, "--role", "control"); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Registry volume synced")

		if _, outErr, err := util.ExecCmd("cubectl", "node", "exec",
			"--role", "control", "--parallel",
			"docker", "restart", "registry",
		); err != nil {
			return errors.Wrap(err, outErr)
		}
		zap.L().Info("Docker registry restarted")

		return nil
	},
}

var cmdDockerCheckImage = &cobra.Command{
	Use:   "check-image <images file>",
	Short: "Check docker images on private registry",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := dockerCheckImage(args[0]); err != nil {
			return errors.WithStack(err)
		}
		zap.L().Info("All images imported")

		return nil
	},
}

func init() {
	m := NewModule("docker")
	m.commitFunc = commitDocker
	m.resetFunc = resetDocker
	m.statusFunc = statusDocker
	m.repairFunc = repairDocker
	m.AddCustomCommand(cmdDockerImportRegistry)
	m.AddCustomCommand(cmdDockerCheckImage)
}
