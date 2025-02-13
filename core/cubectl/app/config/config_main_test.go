package config

import (
	"fmt"
	"testing"

	"github.com/kami-zh/go-capturer"
	"github.com/spf13/cobra"
	"github.com/stretchr/testify/assert"
	"go.uber.org/zap"
)

func commitDummy1() error {
	zap.S().Debugf("Executing commitDummy1()")
	fmt.Println("commit1")
	return nil
}

func resetDummy1() error {
	zap.S().Debugf("Resetting commitDummy1()")
	fmt.Println("reset1")
	return nil
}

func commitDummy2() error {
	zap.S().Debugf("Executing commitDummy2()")
	fmt.Println("commit2")
	return nil
}

func resetDummy2() error {
	zap.S().Debugf("Resetting commitDummy2()")
	fmt.Println("reset2")
	return nil
}

func init() {
	m1 := NewModule("dummy1")
	m1.commitFunc = commitDummy1
	m1.resetFunc = resetDummy1
	m2 := NewModule("dummy2")
	m2.commitFunc = commitDummy2
	m2.resetFunc = resetDummy2
}

func TestConfigMainCommit(t *testing.T) {
	modOrder = []string{"dummy1", "dummy2"}

	t.Run("AllModules", func(t *testing.T) {
		out := capturer.CaptureOutput(func() {
			_ = runConfigCommand(&cobra.Command{Use: "commit"}, []string{"all"})
		})

		assert.Equal(t, "commit1\ncommit2\n", out)
	})

	t.Run("TwoModules", func(t *testing.T) {
		out := capturer.CaptureOutput(func() {
			_ = runConfigCommand(&cobra.Command{Use: "commit"}, []string{"dummy1", "dummy2"})
		})

		assert.Equal(t, "commit1\ncommit2\n", out)
	})

	t.Run("ModulesWithError", func(t *testing.T) {
		err := runConfigCommand(&cobra.Command{Use: "commit"}, []string{"xxx"})
		assert.Error(t, err)
	})
}

func TestConfigMainReset(t *testing.T) {
	modOrder = []string{"dummy1", "dummy2"}

	t.Run("AllModules", func(t *testing.T) {
		out := capturer.CaptureOutput(func() {
			_ = runConfigCommand(&cobra.Command{Use: "reset"}, []string{"all"})
		})

		assert.Equal(t, "reset2\nreset1\n", out)
	})

	t.Run("TwoModules", func(t *testing.T) {
		out := capturer.CaptureOutput(func() {
			_ = runConfigCommand(&cobra.Command{Use: "reset"}, []string{"dummy1", "dummy2"})
		})

		assert.Equal(t, "reset1\nreset2\n", out)
	})
}
