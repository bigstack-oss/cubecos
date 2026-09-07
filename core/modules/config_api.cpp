// CUBE SDK

#include "include/role_cubesys.h"
#include <cluster.hpp>
#include <cube/systemd_util.h>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/log.h>
#include <hex/logrotate.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <unistd.h>

#define MARKER_API_IDP "/etc/appliance/state/api_idp_done"

static const char API_NAME[] = "cube-cos-api";
static const char API_CONF_IN[] = "/etc/cube/api/cube-cos-api.yaml.in";
static const char API_CONF[] = "/etc/cube/api/cube-cos-api.yaml";

// cube-cos-api's own keystone identity for S3. Its "accessKey" setting is a keystone
// user name, and it defaulted to admin -- so the API minted an EC2 credential for the
// admin user while sdk_health and cube_cluster_start_cluster listed, cached and
// recreated admin's credentials for the health log upload. Each side could delete the
// other's key. Issue #703.
static const char API_S3USER[] = "cube-cos-api";
static const char API_S3PASS[] = "Zt7QaXwNsL2mEyKd";

static bool s_bCubeModified = false;
static bool s_bMongodbModified = false;

static CubeRole_e s_eCubeRole;

// use external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_STR(MONGODB_DBPASS);

// own tunings
// The secret half of that EC2 credential. Salted like the mongodb password so it is not
// the same on every cluster; the API creates the credential itself from this value.
CONFIG_TUNING_STR(API_S3_SECRET, "api.s3.secret", TUNING_UNPUB, "Set cube-cos-api s3 credential secret.", API_S3PASS, ValidateRegex, DFT_REGEX_STR);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_STR(s_dbPass, MONGODB_DBPASS, 2);
PARSE_TUNING_STR(s_s3Secret, API_S3_SECRET);

// external global variables
// we still need to listen to changes on MGMT_ADDR to restart cube-cos-api
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// rotate daily and enable copytruncate
static LogRotateConf log_conf(API_NAME, "/var/log/cube-cos-api/*.log", DAILY, 128, 0, true);

static bool
ParseCube(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
ParseMongodb(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyMongodb(bool modified)
{
    s_bMongodbModified = IsModifiedTune(2);
}

static bool
WriteApiConf(const std::string& mongodbPass, const std::string& s3Secret)
{
    if (HexSystemF(0, "sed -e \"s/@MONGODB_ADMIN_ACCESS@/%s/\""
                      " -e \"s/@S3_ACCESS_KEY@/%s/\""
                      " -e \"s/@S3_SECRET_KEY@/%s/\" %s > %s",
                      mongodbPass.c_str(), API_S3USER, s3Secret.c_str(),
                      API_CONF_IN, API_CONF) != 0) {
        HexLogError("failed to update %s", API_CONF);
        return false;
    }

    return true;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | s_bMongodbModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel)) {
        return true;
    }

    std::string sharedId = G(SHARED_ID);
    if (access(MARKER_API_IDP, F_OK) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " api_idp_config %s", sharedId.c_str());
        HexSystemF(0, "touch %s", MARKER_API_IDP);
    }

    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string s3Secret = GetSaltKey(s_saltkey, s_s3Secret.newValue(), s_seed.newValue());

    // The keystone user and EC2 credential the API signs its S3 requests with. Control
    // nodes only: that is where keystone is reachable, and the sdk drives the openstack
    // CLI. Passing the secret keeps keystone and the config file in agreement -- the API
    // would otherwise create the credential itself and ignore the 409 on a rotation.
    if (IsControl(s_eCubeRole))
        HexUtilSystemF(0, 0, HEX_SDK " api_s3_user_setup %s %s", API_S3USER, s3Secret.c_str());
    if (!WriteApiConf(dbPass, s3Secret)) {
        return false;
    }

    // start cube-cos-api
    WriteLogRotateConf(log_conf);
    return SystemdCommitService(true, API_NAME, true);
}

CONFIG_MODULE(api, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(api, cube_scan);
// api_s3_user_setup drives the openstack CLI, so keystone must already be serving.
// api already sorted after it through apache2; this states the reason.
CONFIG_REQUIRES(api, keystone);
CONFIG_REQUIRES(api, mongodb);
CONFIG_REQUIRES(api, keycloak);
CONFIG_REQUIRES(api, influxdb);
CONFIG_REQUIRES(api, cyborg);
CONFIG_REQUIRES(api, apache2);

// extra tunings
CONFIG_OBSERVES(api, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(api, mongodb, ParseMongodb, NotifyMongodb);
