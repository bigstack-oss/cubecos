// CUBE SDK

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

// The zero-touch install agent (phone-home-agent) persists its last preflight
// result to /run during the installer session and, via hex_autoinstall, to
// /var/support in the booted OS; --report renders it without the driver.
static int
PreflightReportMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="preflight_report" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, "/usr/sbin/phone-home-agent", "--report", NULL);

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "agent",
         "Work with the node's zero-touch install agent.",
         !HexStrictIsErrorState());

CLI_MODE_COMMAND("agent", "preflight_report", PreflightReportMain, NULL,
    "Show this node's last zero-touch preflight report (network-validation result).",
    "preflight_report");
