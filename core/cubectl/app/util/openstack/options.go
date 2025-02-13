package openstack

import (
	"os"

	"github.com/gophercloud/gophercloud"
)

var (
	DefaultEndpointOpts = gophercloud.EndpointOpts{
		Region: os.Getenv("OS_REGION_NAME"),
	}
)

type Options struct {
	ConfFile         string `json:"confFile"`
	IdentityEndpoint string `json:"identityEndpoint"`
	AuthType         string `json:"authType"`

	UserID   string `json:"userID"`
	Username string `json:"username"`

	Password string `json:"password"`
	Passcode string `json:"passcode"`

	TenantID    string `json:"tenantID"`
	TenantName  string `json:"tenantName"`
	ProjectName string `json:"projectName"`

	DomainID          string `json:"domainID"`
	DomainName        string `json:"domainName"`
	ProjectDomainName string `json:"projectDomainName"`
	UserDomainName    string `json:"userDomainName"`

	IdentityAPIVersion string `json:"identityAPIVersion"`
	ImageAPIVersion    string `json:"imageAPIVersion"`

	Scope *gophercloud.AuthScope `json:"scope"`
}

func ConfFile(confFile string) Option {
	return func(o *Options) {
		o.ConfFile = confFile
	}
}

func IdentityEndpoint(identityEndpoint string) Option {
	return func(o *Options) {
		o.IdentityEndpoint = identityEndpoint
	}
}

func AuthType(authType string) Option {
	return func(o *Options) {
		o.AuthType = authType
	}
}

func UserID(userID string) Option {
	return func(o *Options) {
		o.UserID = userID
	}
}

func Username(username string) Option {
	return func(o *Options) {
		o.Username = username
	}
}

func Password(password string) Option {
	return func(o *Options) {
		o.Password = password
	}
}

func Passcode(passcode string) Option {
	return func(o *Options) {
		o.Passcode = passcode
	}
}

func TenantID(tenantID string) Option {
	return func(o *Options) {
		o.TenantID = tenantID
	}
}

func TenantName(tenantName string) Option {
	return func(o *Options) {
		o.TenantName = tenantName
	}
}

func ProjectName(projectName string) Option {
	return func(o *Options) {
		o.ProjectName = projectName
	}
}

func DomainID(domainID string) Option {
	return func(o *Options) {
		o.DomainID = domainID
	}
}

func DomainName(domainName string) Option {
	return func(o *Options) {
		o.DomainName = domainName
	}
}

func ProjectDomainName(projectDomainName string) Option {
	return func(o *Options) {
		o.ProjectDomainName = projectDomainName
	}
}

func UserDomainName(userDomainName string) Option {
	return func(o *Options) {
		o.UserDomainName = userDomainName
	}
}

func IdentityAPIVersion(identityAPIVersion string) Option {
	return func(o *Options) {
		o.IdentityAPIVersion = identityAPIVersion
	}
}

func ImageAPIVersion(imageAPIVersion string) Option {
	return func(o *Options) {
		o.ImageAPIVersion = imageAPIVersion
	}
}

func Scope(scope *gophercloud.AuthScope) Option {
	return func(o *Options) {
		o.Scope = scope
	}
}

type Credential struct {
	AccessKey string
	SecretKey string
}
