package settings

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"

	"cubectl/util"
	cubeTesting "cubectl/util/testing"
)

func TestSettings(t *testing.T) {
	testClean := func() {
		os.Remove(SettingsBootFile)
	}
	t.Cleanup(testClean)
	testClean()

	t.Run("Control", func(t *testing.T) {
		settingsText := `
cubesys.role = control
cubesys.management = eth0
cubesys.ha = true
cubesys.controller = control-v
cubesys.control.vip = 127.0.0.10
net.if.addr.eth0=127.0.0.1
net.hostname=control-1
cubesys.control.addrs = 127.0.0.1,127.0.0.2
`

		if err := cubeTesting.GenerateSettingsRaw(SettingsBootFile, settingsText); err != nil {
			t.Fatal(err)
		}

		s := New()
		if err := s.Load(); err != nil {
			t.Error(err)
		}

		tests := []struct {
			name   string
			result interface{}
			expect interface{}
		}{
			{"GetRole", s.GetRole(), "control"},
			{"GetHostname", s.GetHostname(), "control-1"},
			{"GetMgmtIfIp", s.GetMgmtIfIp(), "127.0.0.1"},
			{"GetControllerIp", s.GetControllerIp(), "127.0.0.10"},
			{"GetControlGroupIPs", s.GetControlGroupIPs(), []string{"127.0.0.1", "127.0.0.2"}},
			{"GetMasterControllerIp", s.GetMasterControllerIp(), "127.0.0.1"},
			{"GetController", s.GetController(), "control-v"},
			{"IsHA", s.IsHA(), true},
			{"IsMasterControl", s.IsMasterControl(), true},
			{"IsRole1", s.IsRole(util.ROLE_CONTROL), true},
			{"IsRole2", s.IsRole(util.ROLE_COMPUTE), false},
		}
		for _, test := range tests {
			assert.Equal(t, test.expect, test.result)
		}
	})

	t.Run("Compute", func(t *testing.T) {
		settingsText := `
cubesys.role = compute
cubesys.controller = control-v
cubesys.controller.ip = 127.0.0.10
net.hostname=compute-1
`

		if err := cubeTesting.GenerateSettingsRaw(SettingsBootFile, settingsText); err != nil {
			t.Fatal(err)
		}

		s := New()
		if err := s.Load(); err != nil {
			t.Error(err)
		}

		assert.Equal(t, "compute", s.GetRole())
		assert.Equal(t, "127.0.0.10", s.GetControllerIp())
		assert.Equal(t, "control-v", s.GetController())
		assert.Equal(t, false, s.IsMasterControl())
		assert.Equal(t, false, s.IsRole(util.ROLE_CONTROL))
		assert.Equal(t, true, s.IsRole(util.ROLE_COMPUTE))
	})

	t.Run("Bad", func(t *testing.T) {
		settingsText := ``

		if err := cubeTesting.GenerateSettingsRaw(SettingsBootFile, settingsText); err != nil {
			t.Fatal(err)
		}

		// Global settings
		err := Load()
		if err != nil {
			t.Error(err)
		}

		assert.Equal(t, "", GetRole())
		assert.Equal(t, "", GetHostname())
		assert.Equal(t, "", GetMgmtIfIp())
	})
}

func TestSettingsFileNotFound(t *testing.T) {
	err := New().Load()

	assert.EqualError(t, err, "open "+SettingsBootFile+": no such file or directory")
}

func TestSettingsLoadMap(t *testing.T) {
	testSettings := New()

	settingsMap := map[string]string{
		"a": "1",
		"b": "2",
	}

	testSettings.LoadMap(settingsMap)
	assert.Equal(t, "1", testSettings.V().GetString("a"))
	assert.Equal(t, "2", testSettings.V().GetString("b"))
}
