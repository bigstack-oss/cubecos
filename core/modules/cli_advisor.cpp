// CUBE SDK

#include <sys/stat.h>
#include <unistd.h>

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

// Operator commands for the Cube AI Advisor agent.
//
// A separate mode from "agent", which belongs to the zero-touch install agent
// (phone-home-agent). Two different agents with two different lifetimes: one
// runs during installation, this one is a day-2 daemon a customer enrols
// deliberately.
//
// The work lives in hex_sdk (advisor_enroll, advisor_verify_release); this is
// the thin operator-facing layer, as elsewhere in the CLI.

static const char* ADVISOR_AGENT = "/usr/local/bin/cube-advisor-agent";

// Writes the pairing token to a file only its owner can read, and returns the
// path.
//
// The token is deliberately never an argv element. A token passed as an
// argument appears in `ps` for every user on the box and in the CLI's own
// history, and enrolment is precisely when a working credential exists to leak.
// It lives on tmpfs and is removed as soon as enrolment returns.
static bool
WriteTokenFile(const std::string& token, std::string* path)
{
    char tmpl[] = "/run/advisor-token.XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) {
        CliPrintf("Could not create a temporary file for the pairing token.");
        return false;
    }
    if (fchmod(fd, 0600) != 0) {
        close(fd);
        unlink(tmpl);
        return false;
    }
    ssize_t n = write(fd, token.c_str(), token.size());
    close(fd);
    if (n != (ssize_t)token.size()) {
        unlink(tmpl);
        return false;
    }
    *path = tmpl;
    return true;
}

static int
EnrollMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="enroll" [1]=server [2]=version */)
        return CLI_INVALID_ARGS;

    std::string server, version, token;

    if (!CliReadInputStr(argc, argv, 1, "Advisor service URL: ", &server) || server.length() <= 0)
        return CLI_INVALID_ARGS;
    if (!CliReadInputStr(argc, argv, 2, "Agent version to install: ", &version) || version.length() <= 0)
        return CLI_INVALID_ARGS;

    // Prompted, never taken from argv -- see WriteTokenFile.
    if (!CliReadLine("Pairing token: ", token) || token.length() <= 0) {
        CliPrintf("A pairing token is required. Ask your Advisor administrator to issue one.");
        return CLI_INVALID_ARGS;
    }

    std::string tokenPath;
    if (!WriteTokenFile(token, &tokenPath))
        return CLI_UNEXPECTED_ERROR;

    int rc = HexSpawn(0, HEX_SDK, "advisor_enroll",
                      server.c_str(), tokenPath.c_str(), version.c_str(), NULL);

    // Removed whatever happened. A pairing token left on disk after a failed
    // enrolment is a credential nobody is watching.
    unlink(tokenPath.c_str());

    if (rc != 0) {
        CliPrintf("Enrolment did not complete. Nothing was changed on this node.");
        return CLI_FAILURE;
    }
    return CLI_SUCCESS;
}

static int
StatusMain(int argc, const char** argv)
{
    if (argc > 1)
        return CLI_INVALID_ARGS;

    if (access(ADVISOR_AGENT, X_OK) != 0) {
        CliPrintf("The Advisor agent is not installed on this node.");
        return CLI_SUCCESS;
    }
    HexSpawn(0, (char*)ADVISOR_AGENT, "status", NULL);
    return CLI_SUCCESS;
}

// Verifying a downloaded release without installing it. Useful for the offline
// path, where an operator brings a release in on media and wants to know it is
// genuine before doing anything with it.
static int
VerifyMain(int argc, const char** argv)
{
    if (argc != 2 /* [0]="verify" [1]=directory */)
        return CLI_INVALID_ARGS;

    if (HexSpawn(0, HEX_SDK, "advisor_verify_release", argv[1], NULL) != 0) {
        CliPrintf("The release in %s did not verify. Do not install it.", argv[1]);
        return CLI_FAILURE;
    }
    CliPrintf("The release in %s is signed by Bigstack and its artifacts match.", argv[1]);
    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "advisor",
         "Work with the Cube AI Advisor agent.",
         !HexStrictIsErrorState());

CLI_MODE_COMMAND("advisor", "enroll", EnrollMain, NULL,
    "Install and enrol the Advisor agent on this node.",
    "enroll [<service-url> [<version>]]");

CLI_MODE_COMMAND("advisor", "status", StatusMain, NULL,
    "Show whether this node is enrolled with the Advisor, and as which cluster.",
    "status");

CLI_MODE_COMMAND("advisor", "verify", VerifyMain, NULL,
    "Verify a downloaded Advisor release without installing it.",
    "verify <directory>");
