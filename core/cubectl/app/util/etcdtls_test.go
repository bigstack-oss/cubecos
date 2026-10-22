package util

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestEtcdTLSMode(t *testing.T) {
	savedDir, savedMarker := EtcdPKIDir, EtcdTLSCompatMarker
	t.Cleanup(func() { EtcdPKIDir, EtcdTLSCompatMarker = savedDir, savedMarker })

	tests := []struct {
		name   string
		pki    bool
		marker bool
		want   EtcdTLSMode
	}{
		{"NoPKI", false, false, EtcdTLSPlain},
		{"NoPKIStrayMarker", false, true, EtcdTLSPlain},
		{"PKIAndMarker", true, true, EtcdTLSCompat},
		{"PKIOnly", true, false, EtcdTLSEnforce},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			EtcdPKIDir = filepath.Join(dir, "etcd-pki")
			EtcdTLSCompatMarker = filepath.Join(dir, "etcd_tls_compat")
			if test.pki {
				os.MkdirAll(EtcdPKIDir, 0700)
				os.WriteFile(EtcdCACertFile(), []byte("x"), 0644)
			}
			if test.marker {
				os.WriteFile(EtcdTLSCompatMarker, nil, 0644)
			}
			assert.Equal(t, test.want, GetEtcdTLSMode())
		})
	}
}
