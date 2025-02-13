package config

import (
	"fmt"

	"github.com/spf13/cobra"
	"go.uber.org/zap"
)

type Module struct {
	name       string
	commitFunc func() error
	resetFunc  func() error
	statusFunc func() error
	checkFunc  func() error
	repairFunc func() error
	command    *cobra.Command
}

type CommitOpts struct {
	force bool
}

type ResetOpts struct {
	hard bool
}

var (
	modMap   = map[string]*Module{}
	modOrder = []string{"cluster", "host", "docker", "k3s", "keycloak", "rancher"}

	commitOpts CommitOpts
	resetOpts  ResetOpts
)

func NewModule(name string) *Module {
	m := &Module{
		name: name,
		//commitFunc,
		//resetFunc,
		command: &cobra.Command{
			Use:   name + " <subcommand>",
			Short: "Custom commands in module",
		},
	}
	modMap[name] = m

	return m
}

func (m *Module) AddCustomCommand(cmd *cobra.Command) {
	m.command.AddCommand(cmd)
}

/* func getOrderModules(modules []string) []Module {
	list := modOrder
	if len(modules) > 0 {
		list = modules
	}

	var mods []Module
	for _, name := range list {
		if mod, ok := modMap[name]; ok {
			mods := append(mods, mod)
		} else {
			zap.S().Warnf("Module: %s not found", name)
		}
	}

	return mods
} */

func runConfigCommand(cmd *cobra.Command, args []string) error {
	var modules []string
	if len(args) == 1 && args[0] == "all" {
		if cmd.Name() == "reset" {
			for i := len(modOrder) - 1; i >= 0; i-- {
				modules = append(modules, modOrder[i])
			}
		} else {
			modules = modOrder
		}
	} else {
		modules = args
	}

	for _, name := range modules {
		if mod, ok := modMap[name]; ok {
			var cmdFunc func() error
			switch cmd.Name() {
			case "commit":
				cmdFunc = mod.commitFunc
			case "reset":
				cmdFunc = mod.resetFunc
			case "status":
				cmdFunc = mod.statusFunc
			case "check":
				cmdFunc = mod.checkFunc
			case "repair":
				cmdFunc = mod.repairFunc
			}

			if cmdFunc != nil {
				zap.L().Debug("Executing module", zap.String("module", name), zap.String("command", cmd.Name()))
				if err := cmdFunc(); err != nil {
					if cmd.Name() == "commit" || cmd.Name() == "check" {
						return err
					}

					zap.L().Warn(err.Error())
				}
			} else {
				zap.L().Debug("Module's command not defined", zap.String("module", name), zap.String("command", cmd.Name()))
			}
		} else {
			return fmt.Errorf("%s module not found", name)
		}

	}

	return nil
}

var cmdConfigCommit = &cobra.Command{
	Use:   "commit <modules...>",
	Short: "Commit changes",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runConfigCommand,
}

var cmdConfigReset = &cobra.Command{
	Use:   "reset <modules...>",
	Short: "reset changes",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runConfigCommand,
}

var cmdConfigStatus = &cobra.Command{
	Use:   "status <modules...>",
	Short: "Show config status",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runConfigCommand,
}

var cmdConfigCheck = &cobra.Command{
	Use:   "check <modules...>",
	Short: "Check if config is good",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runConfigCommand,
}

var cmdConfigRepair = &cobra.Command{
	Use:   "repair <modules...>",
	Short: "Repair config",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runConfigCommand,
}

func InitConfigModules(cmdConfig *cobra.Command) {
	cmdConfig.AddCommand(cmdConfigCommit)
	cmdConfig.AddCommand(cmdConfigReset)
	cmdConfig.AddCommand(cmdConfigStatus)
	cmdConfig.AddCommand(cmdConfigCheck)
	cmdConfig.AddCommand(cmdConfigRepair)

	// Module specific commands
	for _, m := range modMap {
		if len(m.command.Commands()) > 0 {
			cmdConfig.AddCommand(m.command)
		}
	}
}

func init() {
	cmdConfigCommit.Flags().BoolVar(&commitOpts.force, "force", false, "Force commit")
	cmdConfigReset.Flags().BoolVar(&resetOpts.hard, "hard", false, "Reset all data")
}
