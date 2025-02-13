package testing

import (
	"cubectl/util"
	"fmt"
	"strings"
)

type Namespace struct {
	namespace string
}

type Container struct {
	Namespace
	image    string
	id       string
	IP       string
	Hostname string
}

func ContainerNS(ns string) *Namespace {
	return &Namespace{namespace: ns}
}

func NewContainer(image string) *Container {
	return &Container{image: image}
}

func (n *Namespace) NewContainer(image string) *Container {
	return &Container{
		Namespace: Namespace{namespace: n.namespace},
		image:     image,
	}
}

func (n *Namespace) List() []Container {
	out, _, err := util.ExecShf("podman --namespace=%s ps -aq --no-trunc", n.namespace)
	if err != nil {
		return nil
	}

	containers := []Container{}
	for _, id := range strings.Split(out, "\n") {
		if id != "" {
			containers = append(containers, Container{id: id})
		}
	}
	return containers
}

func (n *Namespace) CleanupContainers() {
	//_, _, _ = util.ExecShf("podman stop $(podman --namespace=%s ps -aq)", n.namespace)
	//_, _, _ = util.ExecShf("podman rm $(podman --namespace=%s ps -aq)", n.namespace)

	// containers := n.List()
	// for _, c := range containers {
	// 	_ = c.Stop()
	// 	_ = c.Remove()
	// }

	util.ExecCmd("podman", "--namespace="+n.namespace,
		"rm", "--all", "--force")

	util.ExecCmd("podman", "--namespace="+n.namespace,
		"volume", "prune", "--force")

	util.ExecCmd("podman", "--namespace="+n.namespace,
		"pod", "rm", "--all", "--force")
}

func CleanupContainers() {
	ContainerNS("").CleanupContainers()
}

func (c *Container) Run(opts []string, cmdArgs ...string) (string, string, error) {
	allArgs := []string{}
	allArgs = append(allArgs, "--namespace="+c.namespace)
	allArgs = append(allArgs, "run")
	//allArgs = append(allArgs, "--rm")

	// for podman 1.9.2
	//allArgs = append(allArgs, "--no-healthcheck")
	allArgs = append(allArgs, opts...)
	allArgs = append(allArgs, c.image)
	allArgs = append(allArgs, cmdArgs...)

	return util.ExecCmd("podman", allArgs...)
}

func (c *Container) RunDetach(opts []string, cmdArgs ...string) error {
	out, outErr, err := c.Run(append(opts, "-d"), cmdArgs...)
	if err != nil {
		return fmt.Errorf("%s;%v", outErr, err)
	}

	c.id = strings.TrimSuffix(out, "\n")
	c.Hostname = c.GetHostname()
	c.IP = c.GetIP()
	return nil
}

func (c *Container) Exec(opts []string, cmd string, args ...string) (string, string, error) {
	allArgs := []string{"exec"}
	allArgs = append(allArgs, opts...)
	allArgs = append(allArgs, c.id, cmd)
	allArgs = append(allArgs, args...)

	return util.ExecCmd("podman", allArgs...)
}

// Copy files to container
func (c *Container) CopyTo(opts []string, src string, dstContainer string) (string, string, error) {
	allArgs := []string{"cp"}
	allArgs = append(allArgs, opts...)
	allArgs = append(allArgs, src, c.id+":"+dstContainer)

	return util.ExecCmd("podman", allArgs...)
}

// Copy files from container
func (c *Container) CopyFrom(opts []string, srcContainer string, dst string) (string, string, error) {
	allArgs := []string{"cp"}
	allArgs = append(allArgs, opts...)
	allArgs = append(allArgs, c.id+":"+srcContainer, dst)

	return util.ExecCmd("podman", allArgs...)
}

func (c *Container) Inspect(template string) string {
	out, _, err := util.ExecCmd("podman", "inspect", "-f", template, c.id)
	if err != nil {
		return ""
	}

	return strings.TrimSuffix(out, "\n")
}

func (c *Container) GetStatus() string {
	out, _, err := util.ExecCmd("podman", "inspect", "-f", "{{.State.Status}}", c.id)
	if err != nil {
		return ""
	}
	return strings.TrimSuffix(out, "\n")
}

func (c *Container) GetIP() string {
	out, _, err := util.ExecCmd("podman", "inspect", "-f", "{{.NetworkSettings.IPAddress}}", c.id)
	if err != nil {
		return ""
	}
	return strings.TrimSuffix(out, "\n")
}

func (c *Container) GetHostname() string {
	out, _, err := util.ExecCmd("podman", "inspect", "-f", "{{.Config.Hostname}}", c.id)
	if err != nil {
		return ""
	}
	return strings.TrimSuffix(out, "\n")
}

func (c *Container) Start() error {
	_, _, err := util.ExecCmd("podman", "start", c.id)
	return err
}

func (c *Container) Stop() error {
	_, _, err := util.ExecCmd("podman", "stop", c.id)
	return err
}

func (c *Container) Remove() error {
	_, _, err := util.ExecCmd("podman", "rm", "--force", c.id)
	return err
}
