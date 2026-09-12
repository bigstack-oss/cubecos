// CUBE SDK

#include <cube/cubesys.h>
#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/strict.h>
#include <string>

// Reads stored samples rather than collecting live, so the CLI and the GUI
// cannot disagree. Sample age is printed because a 15-minute sampler with no
// timestamp reads as a broken feature.
static int StorageUsageMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="usage" [1]="[<instance>]" */) {
        return CLI_INVALID_ARGS;
    }

    if (argc == 2) {
        HexSystemF(0, HEX_SDK " storage_usage_get %s", argv[1]);
    } else {
        HexSystemF(0, HEX_SDK " storage_usage_get");
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND("storage", "usage", StorageUsageMain, NULL,
    "Display provisioned and actual used space per pool, or for one instance.",
    "usage [<instance>]");
