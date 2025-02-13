package testing

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestContainerBasic(t *testing.T) {
	t.Run("Run", func(t *testing.T) {
		t.Parallel()

		out, _, err := NewContainer("docker.io/busybox").Run(
			[]string{"--rm"},
			"uname",
		)
		if err != nil {
			t.Fatal(err)
		}

		assert.Equal(t, "Linux\n", out)
	})

	t.Run("RunDetachAndExec", func(t *testing.T) {
		t.Parallel()

		c := NewContainer("docker.io/busybox")
		if err := c.RunDetach([]string{"--net=host"}, "top"); err != nil {
			t.Fatal(err)
		}
		defer func() {
			c.Stop()
			c.Remove()
		}()

		assert.Equal(t, "running", c.GetStatus())

		out, _, err := c.Exec(nil, "sh", "-c", `ps | sed -n "/^PID/ {n;p}"`)
		assert.Equal(t, "    1 root      0:00 top\n", out)
		assert.Equal(t, nil, err)

		c.Stop()
		assert.Equal(t, "exited", c.GetStatus())
		c.Remove()
		assert.Equal(t, "", c.GetStatus())
	})

	t.Run("CopyTo", func(t *testing.T) {
		t.Parallel()

		c := NewContainer("docker.io/busybox")
		if err := c.RunDetach([]string{"-ti"}, "sh"); err != nil {
			t.Fatal(err)
		}
		defer func() {
			c.Stop()
			c.Remove()
		}()

		if _, outErr, err := c.CopyTo(nil, "/root/.bash_logout", "/root/"); err != nil {
			t.Fatal(outErr, err)
		}

		if _, outErr, err := c.Exec(nil, "test", "-e", "/root/.bash_logout"); err != nil {
			t.Fatal(outErr, err)
		}
	})

}

func TestContainerNamespace(t *testing.T) {
	ns1 := ContainerNS(t.Name() + "-NS1")
	ns2 := ContainerNS(t.Name() + "-NS2")
	testClean := func() {
		ns1.CleanupContainers()
		ns2.CleanupContainers()
	}
	testClean()
	t.Cleanup(testClean)

	if containers := ns1.List(); len(containers) > 0 {
		t.Fatalf("Incorrect num of containers in %s, num=%d", ns1.namespace, len(containers))
	}
	if containers := ns2.List(); len(containers) > 0 {
		t.Fatalf("Incorrect num of containers in %s, num=%d", ns2.namespace, len(containers))
	}

	ns1c1 := ns1.NewContainer("docker.io/busybox")
	if err := ns1c1.RunDetach([]string{"--net=host"}, "top"); err != nil {
		t.Fatal(err)
	}
	defer ns1c1.Stop()

	ns1c2 := ns1.NewContainer("docker.io/busybox")
	if err := ns1c2.RunDetach([]string{"--net=host"}, "top"); err != nil {
		t.Fatal(err)
	}
	defer ns1c2.Stop()

	ns2c1 := ns2.NewContainer("docker.io/busybox")
	if err := ns2c1.RunDetach([]string{"--net=host"}, "top"); err != nil {
		t.Fatal(err)
	}
	defer ns2c1.Stop()

	if containers := ns1.List(); len(containers) != 2 {
		t.Fatalf("Incorrect num of containers in %s", ns1.namespace)
	} else {
		assert.ElementsMatch(t, []string{ns1c1.id, ns1c2.id}, []string{containers[0].id, containers[1].id})
	}

	if containers := ns2.List(); len(containers) != 1 {
		t.Fatalf("Incorrect num of containers in %s", ns2.namespace)
	} else {
		assert.ElementsMatch(t, []string{ns2c1.id}, []string{containers[0].id})
	}

}
