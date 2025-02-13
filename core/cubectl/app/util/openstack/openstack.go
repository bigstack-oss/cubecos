package openstack

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/gophercloud/gophercloud"
	"github.com/gophercloud/gophercloud/openstack"
	"github.com/gophercloud/gophercloud/openstack/identity/v3/credentials"
	"github.com/gophercloud/gophercloud/openstack/identity/v3/projects"
	"github.com/gophercloud/gophercloud/openstack/identity/v3/users"
)

const (
	opsAuthPath = "/etc/admin-openrc.sh"

	NovaConfFile              = "/etc/nova/nova.conf"
	NovaReservedHostCpus      = "reserved_host_cpus"
	NovaReservedHostMemoryMiB = "reserved_host_memory_mb"
)

var (
	Opts *Options
)

type Option func(*Options)

type IdentityClient struct {
}

func NewConf(file string) (*Options, error) {
	openedFile, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer openedFile.Close()
	s := bufio.NewScanner(openedFile)
	s.Split(bufio.ScanLines)

	opts := &Options{}
	for s.Scan() {
		switch {
		case strings.Contains(s.Text(), "OS_AUTH_URL"):
			words := strings.Split(s.Text(), "=")
			opts.IdentityEndpoint = words[1]
		case strings.Contains(s.Text(), "OS_AUTH_TYPE"):
			words := strings.Split(s.Text(), "=")
			opts.AuthType = words[1]
		case strings.Contains(s.Text(), "OS_USERNAME"):
			words := strings.Split(s.Text(), "=")
			opts.Username = words[1]
		case strings.Contains(s.Text(), "OS_USER_DOMAIN_NAME"):
			words := strings.Split(s.Text(), "=")
			opts.UserDomainName = words[1]
		case strings.Contains(s.Text(), "OS_PASSWORD"):
			words := strings.Split(s.Text(), "=")
			opts.Password = words[1]
		case strings.Contains(s.Text(), "OS_PROJECT_NAME"):
			words := strings.Split(s.Text(), "=")
			opts.TenantName = words[1]
		case strings.Contains(s.Text(), "OS_PROJECT_DOMAIN_NAME"):
			words := strings.Split(s.Text(), "=")
			opts.ProjectDomainName = words[1]
		}
	}

	opts.DomainName = "default"
	systemScope := os.Getenv("OS_SYSTEM_SCOPE")
	if systemScope == "all" {
		opts.Scope = &gophercloud.AuthScope{
			System: true,
		}
	}

	return opts, nil
}

func syncOptions(opts []Option) (*Options, error) {
	options, err := NewConf(opsAuthPath)
	if err != nil {
		return nil, err
	}

	for _, o := range opts {
		o(options)
	}

	return options, nil
}

func NewProvider(opts ...Option) (*gophercloud.ProviderClient, error) {
	syncedOpts, err := syncOptions(opts)
	if err != nil {
		return nil, err
	}

	return openstack.AuthenticatedClient(
		gophercloud.AuthOptions{
			IdentityEndpoint: syncedOpts.IdentityEndpoint,
			UserID:           syncedOpts.UserID,
			Username:         syncedOpts.Username,
			Password:         syncedOpts.Password,
			Passcode:         syncedOpts.Passcode,
			TenantID:         syncedOpts.TenantID,
			TenantName:       syncedOpts.TenantName,
			DomainID:         syncedOpts.DomainID,
			DomainName:       syncedOpts.DomainName,
			Scope:            syncedOpts.Scope,
		},
	)
}

func NewIdentityCli() (*gophercloud.ServiceClient, error) {
	provider, err := NewProvider()
	if err != nil {
		return nil, err
	}

	return openstack.NewIdentityV3(
		provider,
		gophercloud.EndpointOpts{
			Region: os.Getenv("OS_REGION_NAME"),
		},
	)
}

func GetProjectIdByName(identityCli *gophercloud.ServiceClient, projectName string) (string, error) {
	pages, err := projects.List(identityCli, projects.ListOpts{Name: projectName}).AllPages()
	if err != nil {
		return "", err
	}

	projects, err := projects.ExtractProjects(pages)
	if err != nil {
		return "", err
	}

	projectId := ""
	for _, project := range projects {
		if project.Name == projectName {
			projectId = project.ID
			break
		}
	}
	if projectId == "" {
		return "", fmt.Errorf("project %s not found", projectName)
	}

	return projectId, nil
}

func GetUserIdByName(identityCli *gophercloud.ServiceClient, username string) (string, error) {
	pages, err := users.List(identityCli, users.ListOpts{Name: username}).AllPages()
	if err != nil {
		return "", err
	}

	users, err := users.ExtractUsers(pages)
	if err != nil {
		return "", err
	}

	userId := ""
	for _, user := range users {
		if user.Name == username {
			userId = user.ID
			break
		}
	}
	if userId == "" {
		return "", fmt.Errorf("user %s not found", username)
	}

	return userId, nil
}

func CreateEc2Credential(identityCli *gophercloud.ServiceClient, userId, projectId, accessKey, secretKey string) (*Credential, error) {
	_, err := credentials.Create(
		identityCli,
		credentials.CreateOpts{
			UserID:    userId,
			ProjectID: projectId,
			Type:      "ec2",
			Blob:      fmt.Sprintf("{\"access\":\"%s\",\"secret\":\"%s\"}", accessKey, secretKey),
		},
	).Extract()
	if err != nil {
		return nil, err
	}

	return &Credential{
		AccessKey: accessKey,
		SecretKey: secretKey,
	}, nil
}
