// CUBE SDK

#include "cli_iaas_identity.hpp"

// Grant the modern `member` role to every principal still holding the legacy `_member_`
// role. Older CubeCOS releases deleted `member` after keystone bootstrap and handed
// users `_member_`, so upstream policies keyed on role:member never matched (cubecos#216).
// config_keystone bridges the two with an implied role at commit time; this command makes
// the assignments explicit so the bridge stops being load-bearing.
static int
MigrateLegacyMemberRoleMain(int argc, const char** argv)
{
    if (argc != 1)
        return CLI_INVALID_ARGS;

    // the report goes straight to stdout while CliPrintf is buffered, so spawn it first
    // to keep the on-screen order stable
    HexSpawn(0, HEX_SDK, "os_keystone_legacy_member_role_report", NULL);

    CliPrintf("This grants the 'member' role to every user and group that currently holds");
    CliPrintf("the legacy '_member_' role. Existing assignments are left in place.");

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    AutoSignalHandlerMgt hdr(UnInterruptibleHdr);
    if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_keystone_migrate_legacy_member_role", NULL)
        != 0) {
        HexLogError("Could not migrate legacy _member_ role assignments");
        return CLI_UNEXPECTED_ERROR;
    }

    HexLogEvent("IAM01001I", "%s,category=identity,sub=migrate_legacy_member_role",
        CliEventAttrs().c_str());

    return CLI_SUCCESS;
}

// This mode is not available in strict error state
CLI_MODE(CLI_TOP_COMMAND_IAAS, "identity",
    "Work with the IaaS identity service.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("identity", "migrate_legacy_member_role", MigrateLegacyMemberRoleMain, 0,
    "Grant the 'member' role to every principal holding the legacy '_member_' role.",
    "migrate_legacy_member_role");
