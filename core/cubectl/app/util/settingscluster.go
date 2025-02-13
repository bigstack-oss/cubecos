package util

import (
	"sort"

	"github.com/spf13/viper"
)

type NodeIP struct {
	Management     string `json:"management"`
	Provider       string `json:"provider,omitempty"`
	Overlay        string `json:"overlay,omitempty"`
	Storage        string `json:"storage,omitempty"`
	StorageCluster string `json:"storagecluster,omitempty"`
}

type Node struct {
	Hostname string `json:"hostname"`
	Role     string `json:"role"`
	IP       NodeIP `json:"ip"`
	//MemberID string `json:"memberid,omitempty"`
}

type NodeMap map[string]Node

var ClusterSettingsFile = "/etc/settings.cluster.json"

func LoadClusterSettings() (*NodeMap, error) {
	viper := viper.New()
	viper.SetConfigType("json")
	viper.SetConfigFile(ClusterSettingsFile)
	if err := viper.ReadInConfig(); err != nil {
		return nil, err
	}

	nodes := NodeMap{}
	if err := viper.Unmarshal(&nodes); err != nil {
		return nil, err
	}

	return &nodes, nil
}

func (n *NodeMap) GetNodesByRole(roleBits Bits) []Node {
	outNodes := []Node{}

	for _, node := range *n {
		if RoleTest(node.Role, roleBits) {
			outNodes = append(outNodes, node)
		}
	}

	sort.SliceStable(outNodes, func(i, j int) bool {
		if iRole, jRole := outNodes[i].Role, outNodes[j].Role; iRole != jRole {
			return RoleMap[iRole].Order < RoleMap[jRole].Order
		} else {
			return outNodes[i].Hostname < outNodes[j].Hostname
		}
	})

	return outNodes
}

/*
func (n *NodeMap) FindNode(host string) (string, Node, error) {
	for k, v := range *n {
		if v.Hostname == host || v.IP.Management == host {
			return k, v, nil
		}
	}

	return "", Node{}, fmt.Errorf("Unable to find node: %s in cluster", host)
}
*/
