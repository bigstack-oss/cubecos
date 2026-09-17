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

// A test build aims every path below at a scratch tree by compiling this file
// with -DADVISOR_TEST_TREE, the same technique config_advisor.cpp's own test
// uses. Nothing else defines it, so a normal build gets the real root.
#ifdef ADVISOR_TEST_TREE
#define ADVISOR_ROOT ADVISOR_TEST_TREE
#else
#define ADVISOR_ROOT ""
#endif

static const char* ADVISOR_AGENT = ADVISOR_ROOT "/usr/local/bin/cube-advisor-agent";

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
    if (argc > 5 /* [0]="enroll" [1]=server [2]=version [3]=ca-file [4]="force" */)
        return CLI_INVALID_ARGS;

    std::string server, version, token, caFile, force;

    if (!CliReadInputStr(argc, argv, 1, "Advisor service URL: ", &server) || server.length() <= 0)
        return CLI_INVALID_ARGS;
    if (!CliReadInputStr(argc, argv, 2, "Agent version to install: ", &version) || version.length() <= 0)
        return CLI_INVALID_ARGS;

    // Optional, and prompted with an empty answer allowed: an Advisor behind a
    // certificate this node already trusts needs nothing here, while one
    // serving its own -- the normal case offline -- cannot be reached at all
    // without it.
    if (argc > 3)
        caFile = argv[3];
    else
        CliReadLine("Advisor CA file (blank if already trusted): ", caFile);

    // Positional keyword, matching how other cubecos commands take one
    // (app_register's skip_flavor). Never prompted: replacing a working
    // identity is not something to be walked into by pressing return.
    if (argc > 4) {
        if (std::string(argv[4]) != "force") {
            CliPrintf("The fourth argument, if given, must be the word 'force'.");
            return CLI_INVALID_ARGS;
        }
        force = argv[4];
    }

    // Prompted, never taken from argv -- see WriteTokenFile.
    if (!CliReadLine("Pairing token: ", token) || token.length() <= 0) {
        CliPrintf("A pairing token is required. Ask your Advisor administrator to issue one.");
        return CLI_INVALID_ARGS;
    }

    std::string tokenPath;
    if (!WriteTokenFile(token, &tokenPath))
        return CLI_UNEXPECTED_ERROR;

    int rc = HexSpawn(0, HEX_SDK, "advisor_enroll",
                      server.c_str(), tokenPath.c_str(), version.c_str(),
                      caFile.c_str(), force.c_str(), NULL);

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
ConsoleTrustMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="console_trust" [1]=ca-file */)
        return CLI_INVALID_ARGS;

    std::string caFile;
    if (!CliReadInputStr(argc, argv, 1, "Console CA file: ", &caFile) || caFile.length() <= 0)
        return CLI_INVALID_ARGS;

    if (HexSpawn(0, HEX_SDK, "advisor_console_trust", caFile.c_str(), NULL) != 0) {
        CliPrintf("Could not install the console CA. Nothing was changed on this node.");
        return CLI_FAILURE;
    }
    return CLI_SUCCESS;
}

static int
StatusMain(int argc, const char** argv)
{
    if (argc > 1)
        return CLI_INVALID_ARGS;

    // Read separately from whether the agent is installed: a node can hold an
    // allowlist with no agent, and that is worth reporting, not hiding behind
    // a failure below.
    CliList targets;
    if (CliPopulateList(targets, HEX_SDK " advisor_targets_list") == 0)
        CliPrintf("%zu web target(s) allowed through the Advisor.", targets.size());

    if (access(ADVISOR_AGENT, X_OK) != 0) {
        CliPrintf("The Advisor agent is not installed on this node.");
        return CLI_SUCCESS;
    }

    // Whether the unit is running, and any repair for it, is the health
    // framework's job (health_advisor_check / health_advisor_repair), not a
    // second thing printed here.
    HexSpawn(0, (char*)ADVISOR_AGENT, "status", NULL);
    return CLI_SUCCESS;
}

static int
TargetsMain(int argc, const char** argv)
{
    if (argc != 1 /* [0]="targets" */)
        return CLI_INVALID_ARGS;

    // advisor_targets_list prints the allowlist itself; nothing here to
    // reformat or duplicate.
    return HexSpawn(0, HEX_SDK, "advisor_targets_list", NULL) == 0 ? CLI_SUCCESS : CLI_FAILURE;
}

static int
TargetSetMain(int argc, const char** argv)
{
    if (argc != 3 /* [0]="target_set" [1]=name [2]=host:port */)
        return CLI_INVALID_ARGS;

    // Name and address are validated by advisor_targets_set, which also owns
    // the operator-facing refusal text -- not repeated here.
    if (HexSpawn(0, HEX_SDK, "advisor_targets_set", argv[1], argv[2], NULL) != 0)
        return CLI_FAILURE;

    CliPrintf("The Advisor may now reach %s at %s.", argv[1], argv[2]);
    return CLI_SUCCESS;
}

static int
TargetUnsetMain(int argc, const char** argv)
{
    if (argc != 2 /* [0]="target_unset" [1]=name */)
        return CLI_INVALID_ARGS;

    if (HexSpawn(0, HEX_SDK, "advisor_targets_unset", argv[1], NULL) != 0)
        return CLI_FAILURE;

    CliPrintf("%s is no longer reachable through the Advisor.", argv[1]);
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
    "enroll [<service-url> [<version> [<ca-file> [force]]]]");

CLI_MODE_COMMAND("advisor", "console_trust", ConsoleTrustMain, NULL,
    "Accept console sessions signed by the Advisor's CA.",
    "console_trust [<ca-file>]");

CLI_MODE_COMMAND("advisor", "status", StatusMain, NULL,
    "Show whether this node is enrolled with the Advisor, and as which cluster.",
    "status");

CLI_MODE_COMMAND("advisor", "verify", VerifyMain, NULL,
    "Verify a downloaded Advisor release without installing it.",
    "verify <directory>");

CLI_MODE_COMMAND("advisor", "targets", TargetsMain, NULL,
    "List the web endpoints this node will let the Advisor reach.", "targets");

CLI_MODE_COMMAND("advisor", "target_set", TargetSetMain, NULL,
    "Allow the Advisor to reach a web endpoint on this node.", "target_set <name> <host:port>");

CLI_MODE_COMMAND("advisor", "target_unset", TargetUnsetMain, NULL,
    "Stop allowing a web endpoint.", "target_unset <name>");
