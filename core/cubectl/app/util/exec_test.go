package util

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestExecCmdBasic(t *testing.T) {
	tests := map[string]struct {
		app       string
		args      []string
		hasStdout bool
		hasStderr bool
		hasErr    bool
	}{
		"StdoutOnly":       {"pwd", nil, true, false, false},
		"StderrOnly":       {"pwd", []string{"--badopt"}, false, true, true},
		"BothStdoutStderr": {"ls", []string{".", "*.noexist"}, true, true, true},
	}

	for name, test := range tests {
		t.Logf("Testing <%s>", name)
		stdout, stderr, err := ExecCmd(test.app, test.args...)

		assert.Equal(t, test.hasStdout, len(stdout) > 0)
		assert.Equal(t, test.hasStderr, len(stderr) > 0)
		assert.Equal(t, test.hasErr, err != nil)
	}
}

func TestExecCmdOutput(t *testing.T) {
	tests := map[string]struct {
		app    string
		args   []string
		stdout string
		stderr string
		err    error
	}{
		"Stdout": {"echo", []string{"abc"}, "abc\n", "", nil},
		"Stderr": {"ls", []string{"xxx"}, "", "ls: cannot access 'xxx': No such file or directory\n", errors.New("exit status 2")},
	}

	for name, test := range tests {
		t.Logf("Testing <%s>", name)
		stdout, stderr, err := ExecCmd(test.app, test.args...)

		assert.Equal(t, test.stdout, stdout)
		assert.Equal(t, test.stderr, stderr)
		if test.err != nil {
			assert.EqualError(t, err, test.err.Error())
		} else {
			assert.Equal(t, test.err, err)
		}
	}
}

func TestExecCmdEnv(t *testing.T) {
	if out, _, err := ExecCmdEnv([]string{"ENV_TEST=test"}, "env"); err != nil {
		t.Fatal(err)
	} else {
		assert.Contains(t, out, "ENV_TEST=test")
	}
}

func TestExecShOutput(t *testing.T) {
	tests := map[string]struct {
		cmd    string
		stdout string
		stderr string
		err    error
	}{
		"Stdout":              {"echo abc", "abc\n", "", nil},
		"ShellStderrRedirect": {"echo abc 1>&2", "", "abc\n", nil},
		"ShellAndError":       {"echo abc && false", "abc\n", "", errors.New("exit status 1")},
	}

	for name, test := range tests {
		t.Logf("Testing <%s>", name)
		stdout, stderr, err := ExecSh(test.cmd)

		assert.Equal(t, test.stdout, stdout)
		assert.Equal(t, test.stderr, stderr)
		if test.err != nil {
			assert.EqualError(t, err, test.err.Error())
		} else {
			assert.Equal(t, test.err, err)
		}
	}
}
