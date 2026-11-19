// CUBE SDK

#include <stdio.h>

#include <string>

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

// Serving the web UIs on an FQDN (cubesys.fqdn). Every command goes through cube-cos-api
// (hex_sdk api_fqdn_*), which applies a change on every node and then makes the cluster-wide
// part once, so the CLI only collects the input.

// where the certificate files are uploaded, as for a license import
#define STORE_DIR "/var/support"

static int
FqdnShowMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="show" */)
        return CLI_INVALID_ARGS;

    fflush(stdout);
    if (HexSpawn(0, HEX_SDK, "api_fqdn_show", NULL) != 0)
        return CLI_FAILURE;

    return CLI_SUCCESS;
}

static bool
PickStoreFile(int argc, const char** argv, int argidx, const char* what, std::string* file)
{
    int index;
    const std::string cmd = "/usr/bin/find " STORE_DIR "/ -maxdepth 1 -type f -printf '%f\\n' | sort";
    const std::string prompt = std::string("Select the ") + what + " file: ";

    if (CliMatchCmdHelper(argc, argv, argidx, cmd, &index, file, prompt.c_str()) != CLI_SUCCESS) {
        CliPrintf("No such %s file under %s", what, STORE_DIR);
        return false;
    }

    return true;
}

static int
FqdnCertificateMain(int argc, const char** argv)
{
    /* [0]="certificate" [1]=<certificate> [2]=<private key> [3]=<CA certificate> */
    if (argc > 4)
        return CLI_INVALID_ARGS;

    std::string cert, key, ca;
    if (!PickStoreFile(argc, argv, 1, "certificate", &cert) ||
        !PickStoreFile(argc, argv, 2, "private key", &key) ||
        !PickStoreFile(argc, argv, 3, "CA certificate", &ca))
        return CLI_INVALID_ARGS;

    const std::string dir = STORE_DIR "/";
    fflush(stdout);
    if (HexSpawn(0, HEX_SDK, "api_fqdn_cert_install",
                 (dir + cert).c_str(), (dir + key).c_str(), (dir + ca).c_str(), NULL) != 0)
        return CLI_FAILURE;

    CliPrintf("The private key is installed; remove %s from %s.", key.c_str(), STORE_DIR);
    return CLI_SUCCESS;
}

static int
FqdnSetMain(int argc, const char** argv)
{
    /* [0]="set" [1]=<fqdn> */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    std::string fqdn;
    if (!CliReadInputStr(argc, argv, 1, "Enter the FQDN: ", &fqdn) || fqdn.empty())
        return CLI_INVALID_ARGS;

    CliPrintf("The web UIs, Keycloak and the sign-on of every service will move to %s.", fqdn.c_str());
    CliPrintf("Each node then restarts its web services in turn, and sign-on is unavailable for a few minutes.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    fflush(stdout);
    if (HexSpawn(0, HEX_SDK, "api_fqdn_set", fqdn.c_str(), NULL) != 0)
        return CLI_FAILURE;

    return CLI_SUCCESS;
}

static int
FqdnResetMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="reset" */)
        return CLI_INVALID_ARGS;

    CliPrintf("The web UIs, Keycloak and the sign-on of every service will move back to the control VIP");
    CliPrintf("and the appliance's own certificate. Sign-on is unavailable for a few minutes.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    fflush(stdout);
    if (HexSpawn(0, HEX_SDK, "api_fqdn_reset", NULL) != 0)
        return CLI_FAILURE;

    return CLI_SUCCESS;
}

CLI_MODE("cluster", "fqdn",
    "Work with the FQDN the web UIs are served on. Upload the certificate files to " STORE_DIR ".",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("fqdn", "show", FqdnShowMain, NULL,
    "Show the FQDN, the installed certificate and each node's state.",
    "show");

CLI_MODE_COMMAND("fqdn", "certificate", FqdnCertificateMain, NULL,
    "Install the certificate for the FQDN: the certificate (with its intermediates), its unencrypted private key and the root CA that issued it.",
    "certificate <certificate file> <private key file> <CA certificate file>");

CLI_MODE_COMMAND("fqdn", "set", FqdnSetMain, NULL,
    "Serve the web UIs on an FQDN the installed certificate covers.",
    "set <fqdn>");

CLI_MODE_COMMAND("fqdn", "reset", FqdnResetMain, NULL,
    "Remove the FQDN and serve the web UIs on the control VIP again.",
    "reset");
