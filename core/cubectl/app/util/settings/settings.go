package settings

import (
	"bytes"
	"os"
	"strings"

	"github.com/spf13/viper"
	"go.uber.org/zap"

	"cubectl/util"
)

var SettingsBootFile = "/etc/settings.txt"
var SettingsTmpFile = "/tmp/settings.new"

type Settings struct {
	v *viper.Viper
}

var s *Settings

func New() *Settings {
	return &Settings{v: viper.New()}
}

func Load() error { return s.Load() }
func (s *Settings) Load() error {
	s.v.SetConfigType("env")

	settingsFile := SettingsBootFile
	// Use temp settings file during hex_config commit
	if _, err := os.Stat(SettingsTmpFile); err == nil {
		settingsFile = SettingsTmpFile
	}

	zap.S().Debugf("Using settings file %s", settingsFile)
	s.v.SetConfigFile(settingsFile)
	err := s.v.ReadInConfig()
	if err != nil {
		return err
	}
	return nil
}

func LoadMap(m map[string]string) error { return s.LoadMap(m) }
func (s *Settings) LoadMap(m map[string]string) error {
	s.v.SetConfigType("env")

	var content string
	for k, v := range m {
		content += k + "=" + v + "\n"
	}
	zap.L().Debug("settings loaded", zap.String("content", content))

	return s.v.ReadConfig(bytes.NewBuffer([]byte(content)))
}

func V() *viper.Viper { return s.V() }
func (s *Settings) V() *viper.Viper {
	return s.v
}

func IsHA() bool { return s.IsHA() }
func (s *Settings) IsHA() bool {
	return s.v.GetBool("cubesys.ha")
}

func IsMasterControl() bool { return s.IsMasterControl() }
func (s *Settings) IsMasterControl() bool {
	if s.IsRole(util.ROLE_CONTROL) {
		if s.GetMasterControllerIp() == "" {
			return true
		} else {
			if s.GetMasterControllerIp() == s.GetMgmtIfIp() {
				return true
			}
		}
	}

	return false
}

func IsRole(roleBits util.Bits) bool { return s.IsRole(roleBits) }
func (s *Settings) IsRole(roleBits util.Bits) bool {
	return util.RoleMap[s.GetRole()].Role&roleBits > 0
}

func GetRole() string { return s.GetRole() }
func (s *Settings) GetRole() string {
	return s.v.GetString("cubesys.role")
}

func GetHostname() string { return s.GetHostname() }
func (s *Settings) GetHostname() string {
	return s.v.GetString("net.hostname")
}

func GetMgmtIfIp() string { return s.GetMgmtIfIp() }
func (s *Settings) GetMgmtIfIp() string {
	iface := s.v.GetString("cubesys.management")
	return s.v.GetString("net.if.addr." + iface)
}

func GetControllerIp() string { return s.GetControllerIp() }
func (s *Settings) GetControllerIp() string {
	var ip string
	if s.IsRole(util.ROLE_CONTROL) {
		if s.IsHA() {
			ip = s.v.GetString("cubesys.control.vip")
		} else {
			ip = s.GetMgmtIfIp()
		}
	} else {
		ip = s.v.GetString("cubesys.controller.ip")
	}

	return ip
}

func GetController() string { return s.GetController() }
func (s *Settings) GetController() string {
	var name string
	if s.IsRole(util.ROLE_CONTROL) && !s.IsHA() {
		name = s.GetHostname()
	} else {
		name = s.v.GetString("cubesys.controller")
	}

	return name
}

func GetControlGroupIPs() []string { return s.GetControlGroupIPs() }
func (s *Settings) GetControlGroupIPs() []string {
	return strings.Split(s.v.GetString("cubesys.control.addrs"), ",")
}

func GetMasterControllerIp() string { return s.GetMasterControllerIp() }
func (s *Settings) GetMasterControllerIp() string {
	return s.GetControlGroupIPs()[0]
}

func init() {
	s = New()
}
