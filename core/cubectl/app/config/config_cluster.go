package config

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"cubectl/util"
	cubeSettings "cubectl/util/settings"
)

const (
	revisionFile    = "/etc/revision"
	rejoinMarker    = "/run/control_rejoin"
	migrationMarker = "/etc/appliance/state/cube_migration"

	// Backups live outside certsDir on purpose: health_httpd_repair treats any
	// file count other than three as damage and rsyncs the directory back from a
	// peer, which would undo the regeneration.
	certsBackupDir = "/var/lib/cube-certs-backup"

	// config_nova.cpp copies the pem to nova and only does so when its own copy is
	// missing, so a regenerated certificate never reaches nova unless the copy is
	// dropped first.
	novaCertCopy = "/var/lib/nova/certs/server.pem"
)

// certConsumerUnits are the services that read /var/www/certs straight off disk and
// therefore need a restart to pick up a new certificate. haproxy and haproxy-ha are
// restarted as a pair, the same way health_haproxy_repair does it.
//
// Rancher and k3s are deliberately absent: they carry their own platform PKI and
// updating their trust stores is a manual procedure.
var certConsumerUnits = []string{"haproxy", "haproxy-ha", "httpd", "nginx", "cube-cos-api"}

// The Keycloak SAML clients that register the cluster certificate as their signing
// and encryption certificate. Terraform reads /var/www/certs/server.cert only at
// apply time, so once cube-cos-api and the ceph dashboard sign with a new key,
// Keycloak rejects every login ("Invalid requester") until these are applied again.
const (
	keycloakApiModule           = "keycloak_api"
	keycloakCephDashboardModule = "keycloak_ceph_dashboard"

	// What ceph_dashboard_idp_config (sdk_ceph.sh) sets the dashboard SAML SP up
	// with; the port is DASHBOARD_PORT in config_ceph.cpp.
	cephDashboardSsoPort    = "7443"
	keycloakIdpMetadataFile = "/etc/keycloak/saml-metadata.xml"
)

// Seams swapped out by tests.
var (
	terraformApply          = terraformExec
	cephDashboardSsoEnabled = isCephDashboardSsoEnabled
	cephDashboardSsoSetup   = setupCephDashboardSso
)

var genCertsOpts struct {
	force  bool
	dryRun bool
}

var cmdClusterGenCerts = &cobra.Command{
	Use:   "gencerts",
	Short: "Regenerate the cluster's self-signed certificate over the current control group",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		return regenCerts()
	},
}

func isJoined() bool {
	if _, err := os.Stat(revisionFile); os.IsNotExist(err) {
		return false
	}

	return true
}

func isMigration() bool {
	if _, err := os.Stat(migrationMarker); err == nil {
		return true
	}

	return false
}

func commitCluster() error {
	zap.S().Debugf("Executing commitCluster()")

	if cubeSettings.GetRole() == "undef" {
		return nil
	}

	// if !bootstrap {
	// 	return nil
	// }

	if isJoined() {
		zap.S().Infof("Already joined cube cluster")
		if _, outErr, err := util.ExecCmd("cubectl", "this-node", "start"); err != nil {
			return errors.Wrap(err, outErr)
		}
	} else {
		if _, err := os.Stat(rejoinMarker); os.IsNotExist(err) && cubeSettings.IsMasterControl() {
			zap.S().Infof("Creating a new cluster")

			if _, outErr, err := util.ExecCmd("cubectl", "this-node", "new"); err != nil {
				return errors.Wrap(err, outErr)
			}

			if _, err := os.Stat(certFile); os.IsNotExist(err) {
				if err := genSelfSignCerts(); err != nil {
					return errors.WithStack(err)
				}

				zap.L().Info("Self-signed cert generated")
			} else {
				zap.L().Info("Self-signed cert existed")
			}

			// Restore terraform state for cluster IP changes
			if _, err := os.Stat(terraformStateFile); err == nil {
				if err := terraformPushState(); err != nil {
					return errors.WithStack(err)
				}
			}

		} else {
			if _, err := os.Stat(rejoinMarker); err == nil {
				if _, _, err := util.ExecCmd("cubectl", "node", "remove", cubeSettings.GetHostname()); err != nil {
					//return errors.Wrap(err, outErr)
					zap.L().Warn("Failed to remove previous node for rejoining", zap.Error(err))
				} else {
					zap.L().Info("Previous node removed")
				}
			}

			zap.S().Infof("Joining an existing cluster")
			if _, outErr, err := util.ExecCmd("cubectl", "this-node", "join"); err != nil {
				return errors.Wrap(err, outErr)
			}

			if _, _, err := util.ExecCmd("cubectl", "node", "rsync",
				cubeSettings.GetControllerIp()+":"+certsDir,
			); err != nil {
				return errors.WithStack(err)
			}
			zap.L().Info("Cert data synced from cube-controller")

			// wipe leftovers before mirroring the controller's terraform state:
			// stale dirs collide with incoming symlinks (rsync code 23)
			if err := os.RemoveAll(terraformWorkDir); err != nil {
				return errors.WithStack(err)
			}

			if _, outErr, err := util.ExecCmd("cubectl", "node", "rsync",
				cubeSettings.GetControllerIp()+":"+terraformWorkDir,
			); err != nil {
				return errors.Wrap(err, outErr)
			}
			zap.L().Info("Terraform data synced from cube-controller")
		}

		// if cubeSettings.IsRole(util.ROLE_CONTROL) {
		// 	// Ingore error
		// 	if err := terraformInitBackend(); err != nil {
		// 		zap.L().Info(err.Error())
		// 	}
		// 	zap.L().Info("Terraform init with etcd backend")
		// }

	}

	return nil
}

func resetCluster() error {
	if resetOpts.hard {
		os.Remove(terraformStateFile)
	}
	// else {
	// 	if cubeSettings.IsMasterControl() {
	// 		if err := terraformPullState(); err != nil {
	// 			zap.S().Warn(errors.WithStack(err))
	// 		}
	// 	}
	// }

	os.RemoveAll(certsDir)

	if _, _, err := util.ExecCmd("cubectl", "this-node", "reset"); err != nil {
		zap.S().Warn(err)
	}

	return nil
}

// isSelfSignedCert reports whether the certificate at path was issued by itself,
// which is what genSelfSignCerts() produces. Anything else was installed by the
// operator - the FQDN procedure replaces /var/www/certs with the customer's own
// chain - and regenerating over it would swap out the TLS identity of the whole
// site without asking.
func isSelfSignedCert(path string) (bool, error) {
	pemData, err := ioutil.ReadFile(path)
	if err != nil {
		return false, errors.WithStack(err)
	}

	block, _ := pem.Decode(pemData)
	if block == nil {
		return false, errors.Errorf("no PEM block in %s", path)
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return false, errors.WithStack(err)
	}

	return cert.Issuer.String() == cert.Subject.String(), nil
}

// verifyCertCoversControlGroup re-reads a freshly signed certificate and checks that
// every control node actually made it into the SAN.
//
// openssl accepting the -addext argument is not the same as the certificate carrying
// what was asked for, and the whole point of the regeneration is the control group.
func verifyCertCoversControlGroup(path string) error {
	pemData, err := ioutil.ReadFile(path)
	if err != nil {
		return errors.WithStack(err)
	}

	block, _ := pem.Decode(pemData)
	if block == nil {
		return errors.Errorf("no PEM block in %s", path)
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return errors.WithStack(err)
	}

	covered := map[string]bool{}
	for _, ip := range cert.IPAddresses {
		covered["IP:"+ip.String()] = true
	}
	for _, name := range cert.DNSNames {
		covered["DNS:"+name] = true
	}

	// Check against buildCertSANs() itself rather than a second list of the same
	// names: a copy would drift the moment either side gains an entry, and then
	// this check would be passing on the wrong thing.
	var missing []string
	for _, want := range strings.Split(strings.TrimPrefix(buildCertSANs(), "subjectAltName="), ",") {
		if !covered[want] {
			missing = append(missing, want)
		}
	}

	if len(missing) > 0 {
		return errors.Errorf("regenerated certificate is missing %s; leaving the current one in place",
			strings.Join(missing, ", "))
	}

	return nil
}

// backupCerts copies the live certificate aside and returns where it went, so that a
// regeneration that turns out badly can be undone by hand.
func backupCerts() (string, error) {
	// Nothing to preserve on a node whose certificate directory is gone - which is
	// exactly the state someone lands in after trying to force a re-sign by deleting
	// it. Failing here would make gencerts unable to fix the situation it exists for.
	if _, err := os.Stat(certsDir); os.IsNotExist(err) {
		return "", nil
	}

	dir := filepath.Join(certsBackupDir, time.Now().Format("20060102-150405"))
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", errors.WithStack(err)
	}

	if _, outErr, err := util.ExecCmd("cp", "-a", certsDir+".", dir); err != nil {
		return "", errors.Wrap(err, outErr)
	}

	return dir, nil
}

// distributeCerts puts the regenerated certificate in front of every consumer that
// reads it off disk.
//
// The file goes to every node, not just the control group. A compute node holds a
// copy of /var/www/certs from the moment it joins -- config_cluster.go rsyncs the
// directory there regardless of role -- and it is not decoration: nova keeps a copy
// of server.pem, and once the AMQP listener runs TLS every nova and neutron agent
// on that node verifies the broker against this directory. Re-signing without
// syncing it would leave those nodes trusting a certificate the cluster no longer
// presents, and the failure would surface as agents dropping off rather than as
// anything pointing back at this command.
//
// The restart below stays on the control group, because certConsumerUnits are
// control-only services. Nothing on a compute node needs restarting for the new
// file: py-amqp builds its SSL context per connection, reading ca_certs off disk
// each time, so a reconnecting client picks the new certificate up on its own.
func distributeCerts() error {
	if _, outErr, err := util.ExecCmd("cubectl", "node", "rsync",
		certsDir,
	); err != nil {
		return errors.Wrap(err, outErr)
	}
	zap.L().Info("Cert data synced to every node")

	// nova holds a copy rather than reading /var/www/certs, and only refreshes it
	// when the copy is gone. Compute nodes carry that copy too.
	if _, outErr, err := util.ExecCmd("cubectl", "node", "exec",
		"--parallel",
		"rm", "-f", novaCertCopy,
	); err != nil {
		return errors.Wrap(err, outErr)
	}
	zap.L().Info("Stale nova cert copy dropped", zap.String("path", novaCertCopy))

	restart := append([]string{
		"node", "exec", "--role", "control", "--parallel",
		"systemctl", "restart",
	}, certConsumerUnits...)

	if _, outErr, err := util.ExecCmd("cubectl", restart...); err != nil {
		return errors.Wrap(err, outErr)
	}
	zap.L().Info("Cert consumers restarted", zap.Strings("units", certConsumerUnits))

	if err := reconfigureCephCerts(); err != nil {
		zap.S().Warn(err)
	}

	zap.L().Info("Rancher and k3s trust stores are not updated by this command; " +
		"follow the certificate replacement runbook for those")

	return reapplySamlClients()
}

// reapplySamlClients hands the new certificate to both ends of every SAML trust
// that pins it. The controller value matches the shared id the shell paths
// (api_idp_config, ceph_dashboard_idp_config) apply with, so the clients are updated
// in place rather than created anew.
//
// The ceph dashboard is an SP of its own: `sso setup saml2` stored a copy of the old
// certificate and key, and it signs its requests and decrypts assertions with them.
// Its Keycloak client is only applied once the dashboard holds the new pair; giving
// Keycloak the new certificate first would break a dashboard login that still works.
//
// Every step is tried even when another fails, and a failure fails the command: by
// now the new certificate is live and SSO login is broken until the step goes through.
func reapplySamlClients() error {
	ip := cubeSettings.GetControllerIp()
	controller := "cube_controller=" + ip

	var rerun []string
	apply := func(mod string) {
		if err := terraformApply("apply", mod,
			[]string{controller},
			[]string{terraformVarFileKeycloakAdminPassword},
		); err != nil {
			zap.S().Error(err)
			rerun = append(rerun, "terraform-cube.sh apply -auto-approve -target=module."+mod+
				" -var "+controller+" -var-file="+terraformVarFileKeycloakAdminPassword)
			return
		}
		zap.L().Info("Keycloak SAML client updated", zap.String("module", mod))
	}

	apply(keycloakApiModule)

	enabled, err := cephDashboardSsoEnabled()
	switch {
	case err == nil && !enabled:
		zap.L().Info("Ceph dashboard SSO is not enabled, its Keycloak client is left alone")
	case err == nil:
		err = cephDashboardSsoSetup(ip)
	}
	if err != nil {
		zap.S().Error(err)
		rerun = append(rerun,
			strings.Join(cephDashboardSsoSetupArgs(ip), " ")+" && ceph dashboard sso enable saml2")
		rerun = append(rerun, "terraform-cube.sh apply -auto-approve -target=module."+
			keycloakCephDashboardModule+" -var "+controller+" -var-file="+terraformVarFileKeycloakAdminPassword)
	} else if enabled {
		apply(keycloakCephDashboardModule)
	}

	if len(rerun) > 0 {
		return errors.Errorf(
			"the certificate was replaced, but SSO login fails until the SAML clients carry it; "+
				"once terraform-cube.sh can init and Keycloak is reachable, run in order:\n  %s",
			strings.Join(rerun, "\n  "))
	}

	return nil
}

func isCephDashboardSsoEnabled() (bool, error) {
	out, outErr, err := util.ExecCmd("ceph", "dashboard", "sso", "status")
	if err != nil {
		return false, errors.Wrap(err, outErr)
	}

	// SSO is "enabled" with "SAML2" protocol. / SSO is "disabled".
	return strings.Contains(out, `"enabled"`), nil
}

func cephDashboardSsoSetupArgs(ip string) []string {
	return []string{
		"ceph", "dashboard", "sso", "setup", "saml2",
		"https://" + ip + ":" + cephDashboardSsoPort,
		keycloakIdpMetadataFile,
		"username",
		"https://" + ip + ":10443/auth/realms/master",
		certFile, keyFile,
	}
}

// setupCephDashboardSso gives the dashboard SP the new certificate and key, the same
// way ceph_dashboard_idp_config first set it up.
func setupCephDashboardSso(ip string) error {
	for _, args := range [][]string{
		cephDashboardSsoSetupArgs(ip),
		{"ceph", "dashboard", "sso", "enable", "saml2"},
	} {
		if _, outErr, err := util.ExecCmd(args[0], args[1:]...); err != nil {
			return errors.Wrap(err, outErr)
		}
	}
	zap.L().Info("Ceph dashboard SAML SP updated")

	return nil
}

// reconfigureCephCerts hands the new certificate to the two ceph endpoints that were
// given a copy rather than a path. ceph_dashboard_init() is not reusable here: it
// also creates a radosgw user, wires up SAML2 SSO and runs terraform.
func reconfigureCephCerts() error {
	for _, args := range [][]string{
		{"ceph", "dashboard", "set-ssl-certificate", "-i", certFile},
		{"ceph", "dashboard", "set-ssl-certificate-key", "-i", keyFile},
		{"ceph", "config-key", "set", "mgr/restful/crt", "-i", certFile},
		{"ceph", "config-key", "set", "mgr/restful/key", "-i", keyFile},
	} {
		if _, outErr, err := util.ExecCmd(args[0], args[1:]...); err != nil {
			return errors.Wrap(err, outErr)
		}
	}
	zap.L().Info("Ceph dashboard and mgr restful updated")

	return nil
}

// regenCerts re-signs the cluster certificate so that it covers the current control
// group, then puts it in front of every consumer that reads /var/www/certs.
//
// genSelfSignCerts() only ever runs while creating a new cluster, and CONFIG_MIGRATE
// carries /var/www/certs across upgrades untouched, so an existing cluster has no
// other way to pick up a widened SAN. Deleting the certificate and committing does
// not work either: the commit path skips certificate generation once the node has
// joined, and health_httpd_repair rsyncs the old certificate back from a peer.
func regenCerts() error {
	if !cubeSettings.IsMasterControl() {
		return errors.New("certificates are signed on the master control node only")
	}

	if _, err := os.Stat(certFile); err == nil {
		selfSigned, err := isSelfSignedCert(certFile)
		if err != nil {
			return err
		}

		if !selfSigned && !genCertsOpts.force {
			return errors.Errorf(
				"%s was not issued by this cluster, refusing to replace it; "+
					"re-run with --force to overwrite it anyway", certFile)
		}
	}

	sans := buildCertSANs()

	if genCertsOpts.dryRun {
		fmt.Println("subject:  /CN=" + cubeSettings.GetController())
		fmt.Println(sans)
		fmt.Println("would rewrite:      " + certFile + ", " + keyFile + ", " + certKeyFile)
		fmt.Println("would sync to:      every node")
		fmt.Println("would drop:         " + novaCertCopy + " (rebuilt on the next nova commit)")
		fmt.Println("would restart:      " + strings.Join(certConsumerUnits, " "))
		fmt.Println("would reconfigure:  ceph dashboard and mgr restful")
		fmt.Println("would re-apply:     keycloak SAML client " + keycloakApiModule)
		fmt.Println("would re-apply:     ceph dashboard SAML SP (sso setup saml2), then keycloak SAML client " +
			keycloakCephDashboardModule + " (only if dashboard SSO is enabled)")
		fmt.Println("left to the operator: rancher and k3s trust stores")

		return nil
	}

	staging, err := ioutil.TempDir("", "cube-certs")
	if err != nil {
		return errors.WithStack(err)
	}
	defer os.RemoveAll(staging)

	if err := genSelfSignCertsInto(staging); err != nil {
		return err
	}

	// Read the staged certificate back before it goes anywhere: a certificate that
	// openssl accepted but that does not carry the control group would be worse than
	// the one being replaced, and by then nine services would already be serving it.
	if err := verifyCertCoversControlGroup(filepath.Join(staging, certBase)); err != nil {
		return err
	}

	backup, err := backupCerts()
	if err != nil {
		return err
	}
	if backup != "" {
		zap.L().Info("Previous certificate backed up", zap.String("path", backup))
	}

	// The staging sign never touches certsDir, so on a node whose certificate
	// directory is missing there is nothing to copy into yet.
	if err := os.MkdirAll(certsDir, 0755); err != nil {
		return errors.WithStack(err)
	}

	for _, base := range []string{certBase, keyBase, certKeyBase} {
		if _, outErr, err := util.ExecCmd("cp", "-f",
			filepath.Join(staging, base), filepath.Join(certsDir, base),
		); err != nil {
			return errors.Wrap(err, outErr)
		}
	}
	zap.L().Info("Self-signed cert regenerated", zap.String("sans", sans))

	return distributeCerts()
}

func init() {
	m := NewModule("cluster")
	m.commitFunc = commitCluster
	m.resetFunc = resetCluster

	m.AddCustomCommand(cmdClusterGenCerts)
	cmdClusterGenCerts.Flags().BoolVarP(&genCertsOpts.force, "force", "f", false,
		"Replace the certificate even when it was not issued by this cluster")
	cmdClusterGenCerts.Flags().BoolVarP(&genCertsOpts.dryRun, "dry-run", "", false,
		"Print what would be written and leave every file alone")
}
