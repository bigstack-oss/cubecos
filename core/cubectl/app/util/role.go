package util

type Bits uint8

const (
	ROLE_CONTROL Bits = 1 << iota
	ROLE_NETWORK
	ROLE_COMPUTE
	ROLE_STORAGE
	ROLE_EDGE
	ROLE_ALL Bits = ROLE_CONTROL | ROLE_NETWORK | ROLE_COMPUTE | ROLE_STORAGE
	ROLE_CORE Bits = ROLE_EDGE | ROLE_CONTROL | ROLE_COMPUTE | ROLE_STORAGE
)

var RoleMap = map[string]struct {
	Role  Bits
	Order int
}{
	"control":           {ROLE_CONTROL, 0},
	"network":           {ROLE_NETWORK, 1},
	"compute":           {ROLE_COMPUTE, 2},
	"storage":           {ROLE_STORAGE, 3},
	"control-network":   {ROLE_CONTROL | ROLE_NETWORK, -1},
	"control-converged": {ROLE_CONTROL | ROLE_NETWORK | ROLE_COMPUTE | ROLE_STORAGE, -2},
	"edge-core":         {ROLE_EDGE | ROLE_CONTROL | ROLE_COMPUTE | ROLE_STORAGE, -3},
	"moderator":         {ROLE_EDGE | ROLE_CONTROL, -4},
}

func RoleTest(role string, roleBits Bits) bool {
	return RoleMap[role].Role&roleBits > 0
}
