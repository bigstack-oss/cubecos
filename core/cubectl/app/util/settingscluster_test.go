package util

import (
	"io/ioutil"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSettingsCluster(t *testing.T) {
	t.Cleanup(func() {
		os.Remove(ClusterSettingsFile)
	})

	settingsClusterJson := `
{
	"node1":{"hostname":"node1","role":"control","ip":{"management":"1.1.1.1"}},
	"node2":{"hostname":"node2","role":"storage","ip":{"management":"2.2.2.2"}}
}
`
	if err := ioutil.WriteFile(ClusterSettingsFile, []byte(settingsClusterJson), 0644); err != nil {
		t.Fatal(err)
	}

	if nodeMap, err := LoadClusterSettings(); err != nil {
		t.Fatal(err)
	} else {
		assert.Equal(t, "node1", (*nodeMap)["node1"].Hostname)
		assert.Equal(t, "node2", (*nodeMap)["node2"].Hostname)
	}
}
