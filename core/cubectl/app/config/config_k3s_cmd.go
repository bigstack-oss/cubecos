package config

import (
	"cubectl/util"
	"cubectl/util/kube"
	"fmt"
	"os"
	"strings"

	"github.com/pkg/errors"
)

const (
	k3sAdminDirectControlMarkerSecret = "k3s-admin-direct-control-enabled"
)

func disaleK3sAdminDirectControl() error {
	kubeCli.SetSecretClient(kube.DefaultNamespace)
	return kubeCli.DeleteSecret(k3sAdminDirectControlMarkerSecret)
}

func enableK3sAdminDirectControl() error {
	kubeCli.SetSecretClient(kube.DefaultNamespace)
	_, err := kubeCli.CreateTokenSecret(
		k3sAdminDirectControlMarkerSecret,
		kube.DefaultUser,
	)
	if err != nil {
		return err
	}

	return nil
}

func isAdminDirectControlEnabled() bool {
	kubeCli.SetSecretClient(kube.DefaultNamespace)
	secret, err := kubeCli.GetSecret(k3sAdminDirectControlMarkerSecret)
	if err != nil {
		return false
	}

	return secret.Name == k3sAdminDirectControlMarkerSecret
}

func isKubectlOrHelmCmd(cmd string) bool {
	return cmd == "kubectl" || cmd == "helm"
}

// note:
// this function is provided for the hex-cli's k3s module to execute kubectl or helm commands directly
// in case the current hex-cli can't satisfy the operation requirements from the user
//
// reason to use os cmd instead of kube sdk:
// because we don't know what kind of command the user will execute, so cause it's not possible to implement all the sdk based implementations
func k3sExecAdminCmd(cmd string) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	if !isAdminDirectControlEnabled() {
		return errors.New("admin direct control is disabled, refusing to execute command")
	}

	cmdArgs := strings.Split(cmd, " ")
	if len(cmdArgs) == 0 {
		return errors.New("command is empty")
	}
	if !isKubectlOrHelmCmd(cmdArgs[0]) {
		return errors.New("only kubectl and helm commands are allowed")
	}

	os.Setenv("KUBECONFIG", k3sConfigFile)
	out, outErr, err := util.ExecCmd(cmdArgs[0], cmdArgs[1:]...)
	if err != nil {
		return errors.New(outErr)
	}

	fmt.Println(out)
	return nil
}

func k3sEnableAdminExec(operation string) error {
	var err error
	kubeCli, err = kube.NewClient(
		kube.AuthType(kube.OutOfClusterAuth),
		kube.AuthFile(kube.K3sConfigFile),
	)
	if err != nil {
		return err
	}

	switch strings.ToLower(operation) {
	case "yes":
		return enableK3sAdminDirectControl()
	case "no":
		return disaleK3sAdminDirectControl()
	}

	return fmt.Errorf(
		"unsupport operation(%s) to enable/disable k3s admin direct control, only 'yes' or 'no' is allowed",
		operation,
	)
}
