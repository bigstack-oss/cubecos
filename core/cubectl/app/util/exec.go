package util

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"go.uber.org/zap"
)

func _execCmd(envVars []string, name string, args ...string) (string, string, error) {
	cmd := exec.Command(name, args...)
	if envVars != nil {
		cmd.Env = append(os.Environ(), envVars...)
	}

	os.Setenv("PATH", os.Getenv("PATH")+":/usr/local/bin")

	var bOut, bErr bytes.Buffer
	cmd.Stdout = &bOut
	cmd.Stderr = &bErr
	err := cmd.Run()

	zap.L().Debug(
		"Executed command: "+strings.Join(append([]string{name}, args...), " "),
		zap.String("stdout", bOut.String()),
		zap.String("stderr", bErr.String()),
		zap.Error(err),
	)

	return bOut.String(), bErr.String(), err
}

func ExecCmd(name string, args ...string) (string, string, error) {
	return _execCmd(nil, name, args...)
}

func ExecCmdEnv(envVars []string, name string, args ...string) (string, string, error) {
	zap.L().Debug("Env variables", zap.Any("env", envVars))
	return _execCmd(envVars, name, args...)
}

func ExecSh(cmdStr string) (string, string, error) {
	return _execCmd(nil, "/bin/bash", "-c", cmdStr)
}

func ExecShf(format string, a ...interface{}) (string, string, error) {
	return _execCmd(nil, "/bin/bash", "-c", fmt.Sprintf(format, a...))
}
