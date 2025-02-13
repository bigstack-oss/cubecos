package testing

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"cubectl/util"

	"github.com/rs/xid"
)

const (
	etcdClientPort = 12379
	etcdPeerPort   = 12380
)

func (n *Namespace) RunCubeContainer(name string, ip string, role string, extraTunes []string) (*Container, error) {
	os.MkdirAll("/var/lib/mysql/", 0755)
	os.MkdirAll("/root/.ssh/", 0755)

	c := ContainerNS(n.namespace).NewContainer("localhost/cube")

	var cName string
	if n.namespace != "" {
		cName = n.namespace + "_" + name
	} else {
		cName = fmt.Sprintf("%s-%d", name, xid.New().Counter())
	}

	opts := []string{
		"--name=" + cName,
		"--hostname=" + name,
		//"--pod=new:" + name,
		"--ip=" + ip,
		"--privileged",
		"-v", "/usr/local/bin:/usr/local/bin",
		"-v", "/root/workspace/cube/core/cubectl/data/test/hex_config:/usr/sbin/hex_config",
		"-v", "/sys/fs/cgroup/:/sys/fs/cgroup/",
		"-v", "/opt/:/opt/",
		"-v", "/var/lib/mysql/:/var/lib/mysql/",
		"-v", "/root/.ssh/:/root/.ssh/",
		"-v", "/var/lib/rancher/",
	}

	if err := c.RunDetach(opts); err != nil {
		return nil, err
	}

	settings := []string{
		"cubesys.role=" + role,
		"cubesys.management = eth0",
		"cubesys.seed = cube",
		"net.if.addr.eth0=" + ip,
		"net.hostname=" + name,
		//"cubesys.controller.ip=" + control1Ip,
	}

	settings = append(settings, extraTunes...)

	if _, _, err := c.Exec(nil, "sh", "-c", "echo '"+strings.Join(settings, "\n")+"' > /etc/settings.txt"); err != nil {
		return nil, err
	}

	if util.RoleTest(role, util.ROLE_CONTROL) {
		if _, _, err := c.CopyTo(nil, "/var/lib/terraform/", "/var/lib/"); err != nil {
			return nil, err
		}
	}

	// Dummy hex_config
	//if _, _, err := c.Exec(nil, "sh", "-c", "/bin/echo -e '#!/bin/sh\ntrue' > /usr/sbin/hex_config; chmod +x /usr/sbin/hex_config"); err != nil {
	//	return nil, err
	//}

	return c, nil
}

func RunCubeContainer(name string, ip string, role string, extraTunes []string) (*Container, error) {
	return ContainerNS("").RunCubeContainer(name, ip, role, extraTunes)
}

func (c *Container) UpdateSettings(sMap map[string]string) error {
	for k, v := range sMap {
		if _, _, err := c.Exec(nil, "sed", "-i", fmt.Sprintf(`/^%s/c\%s=%s`, k, k, v), "/etc/settings.txt"); err != nil {
			return err
		}
	}

	return nil
}

func RunCubeContainerHostNet(role string, extraTunes []string) (*Container, error) {
	os.MkdirAll("/var/lib/mysql/", 0755)
	os.MkdirAll("/root/.ssh/", 0755)

	c := ContainerNS("").NewContainer("localhost/cube")

	name := "cube-local"
	cName := fmt.Sprintf("%s-%d", name, xid.New().Counter())

	opts := []string{
		"--name=" + cName,
		"--hostname=" + name,
		"--net=host",
		"--privileged",
		"-v", "/usr/local/bin:/usr/local/bin",
		"-v", "/root/workspace/cube/core/cubectl/data/test/hex_config:/usr/sbin/hex_config",
		"-v", "/sys/fs/cgroup/:/sys/fs/cgroup/",
		"-v", "/opt/:/opt/",
		"-v", "/var/lib/mysql/:/var/lib/mysql/",
		"-v", "/root/.ssh/:/root/.ssh/",
	}

	if err := c.RunDetach(opts); err != nil {
		return nil, err
	}

	settings := []string{
		"cubesys.role=" + role,
		"cubesys.management = eth0",
		"cubesys.seed = cube",
		"net.if.addr.eth0=172.17.0.2",
		"net.hostname=" + name,
		//"cubesys.controller.ip=" + control1Ip,
	}

	settings = append(settings, extraTunes...)

	if _, _, err := c.Exec(nil, "sh", "-c", "echo '"+strings.Join(settings, "\n")+"' > /etc/settings.txt"); err != nil {
		return nil, err
	}

	if util.RoleTest(role, util.ROLE_CONTROL) {
		if _, _, err := c.CopyTo(nil, "/var/lib/terraform/", "/var/lib/"); err != nil {
			return nil, err
		}
	}

	return c, nil
}

func (n *Namespace) RunEtcdContainer() (*Container, error) {
	c := n.NewContainer("quay.io/coreos/etcd")
	if err := c.RunDetach(
		[]string{
			"-p", fmt.Sprintf("%d:%d", etcdClientPort, 2379),
		},
		"etcd",
		"--listen-client-urls=http://0.0.0.0:"+strconv.Itoa(2379),
		"--advertise-client-urls=http://0.0.0.0:"+strconv.Itoa(2379),
	); err != nil {
		return nil, err
	}

	return c, nil
}
