package docker

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func withRegistry(t *testing.T, h http.HandlerFunc) {
	srv := httptest.NewServer(h)
	old := LocalRegistry
	LocalRegistry = strings.TrimPrefix(srv.URL, "http://")
	t.Cleanup(func() { LocalRegistry = old; srv.Close() })
}

func TestCubeRegistryReachable(t *testing.T) {
	withRegistry(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v2/" {
			w.WriteHeader(http.StatusNotFound)
		}
	})
	if err := CubeRegistryReachable(); err != nil {
		t.Fatalf("want reachable, got %v", err)
	}
}

func TestCubeRegistryUnreachable(t *testing.T) {
	old := LocalRegistry
	LocalRegistry = "127.0.0.1:1"
	t.Cleanup(func() { LocalRegistry = old })
	if err := CubeRegistryReachable(); err == nil {
		t.Fatal("want error for a closed port")
	}
}

func TestExistsInCubeRegistry(t *testing.T) {
	withRegistry(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodHead || r.URL.Path != "/v2/cephcsi/cephcsi/manifests/v3.13.1" {
			w.WriteHeader(http.StatusNotFound)
		}
	})
	if !ExistsInCubeRegistry(Image{Name: "cephcsi/cephcsi", Tag: "v3.13.1"}) {
		t.Fatal("want present image found")
	}
	if ExistsInCubeRegistry(Image{Name: "cephcsi/cephcsi", Tag: "v0"}) {
		t.Fatal("want missing image not found")
	}
}
