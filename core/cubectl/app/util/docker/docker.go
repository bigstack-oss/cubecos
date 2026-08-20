package docker

import (
	"cubectl/util"
	"fmt"
	"net/http"
	"time"

	"cubectl/util/settings"

	"github.com/pkg/errors"
)

var (
	Binary            = "/usr/bin/docker"
	LocalRegistryPort = "5080"
)

type Image struct {
	Registry string
	Name     string
	Tag      string
	LocalTar string
}

// CAUTION:
// The function below are not the best practice to operate docker in Go.
// The reason we use os/exec to call docker is because "github.com/docker/docker/client" has terrible package conflicts
// with etcd, grpc lib, and other pretty old stuff in this project which causes a lot of trouble.
//
// for example:
// docker requires google.golang.org/grpc >= 1.27.1, but etcd and other libs require google.golang.org/grpc < 1.27.1
// at this moment, we don't have much time to resolve the issue becuase it requires a lot of effort to upgrade and test all existing behaviors.
var manifestTypes = "application/vnd.docker.distribution.manifest.v2+json," +
	"application/vnd.docker.distribution.manifest.list.v2+json," +
	"application/vnd.oci.image.manifest.v1+json," +
	"application/vnd.oci.image.index.v1+json"

// ExistsInCubeRegistry reports whether the node's registry already serves this
// image:tag, so callers can skip an expensive load+push of what is there.
func ExistsInCubeRegistry(image Image) bool {
	url := fmt.Sprintf("http://%s:%s/v2/%s/manifests/%s",
		settings.GetHostname(), LocalRegistryPort, image.Name, image.Tag)
	req, err := http.NewRequest(http.MethodHead, url, nil)
	if err != nil {
		return false
	}
	req.Header.Set("Accept", manifestTypes)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK
}

func PushImageToCubeRegistry(image Image) error {
	_, outErr, err := util.ExecCmd(Binary, "load", "-i", image.LocalTar)
	if err != nil {
		return errors.Wrap(err, outErr)
	}

	officialImage := fmt.Sprintf("%s/%s:%s", image.Registry, image.Name, image.Tag)
	localImage := fmt.Sprintf("%s:%s/%s:%s", settings.GetHostname(), LocalRegistryPort, image.Name, image.Tag)
	_, outErr, err = util.ExecCmd(Binary, "tag", officialImage, localImage)
	if err != nil {
		return errors.Wrap(err, outErr)
	}

	_, outErr, err = util.ExecCmd(Binary, "push", localImage)
	if err != nil {
		return errors.Wrap(err, outErr)
	}

	return nil
}
