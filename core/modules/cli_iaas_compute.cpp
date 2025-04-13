// CUBE SDK

#include <algorithm>

#include <hex/log.h>
#include <hex/strict.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/filesystem.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

static const char* LABEL_SEG_NAME = "Enter instance HA segment name: ";
static const char* LABEL_HOST_LIST = "Enter compute host list [host1,host2,...]: ";
static const char* LABEL_HOST_EVACUATE = "Evacuate which compute node: ";
static const char* LABEL_USER_NAME = "Enter desired login username: ";
static const char* LABEL_PASS = "Enter desired login password/SSH public key: ";

static int
PreFailureHostEvacuationMain(int argc, const char** argv)
{
    /*
     * [0]="pre_failure_host_evacuation|upgrade_host_evacuation", [1]=<hostname>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    int index;
    std::string hostname;

    bool isUpgrade = false;
    if (strcmp(argv[0], "upgrade_host_evacuation") == 0)
        isUpgrade = true;

    std::string cmd = "cubectl node list compute -j | jq -r .[].hostname";
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &hostname, LABEL_HOST_EVACUATE) != CLI_SUCCESS) {
        CliPrintf("Unknown hostname");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_get_instance_list_by_node", hostname.c_str(), NULL);
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSpawn(0, HEX_SDK, "os_pre_failure_host_evacuation", hostname.c_str(), isUpgrade ? "upgrade" : "default", NULL);

    HexLogEvent("CMP01001I", "%s,category=compute,sub=evacuate,target=%s",
                CliEventAttrs().c_str(), hostname.c_str());

    return CLI_SUCCESS;
}

static int
PostFailureHostEvacuationMain(int argc, const char** argv)
{
    /*
     * [0]="post_failure_host_evacuation", [1]=<hostname>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    int index;
    std::string hostname;

    std::string cmd = "cubectl node list compute -j | jq -r .[].hostname";
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &hostname, LABEL_HOST_EVACUATE) != CLI_SUCCESS) {
        CliPrintf("Unknown hostname");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_get_instance_list_by_node", hostname.c_str(), NULL);
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSpawn(0, HEX_SDK, "os_post_failure_host_evacuation", hostname.c_str(), NULL);

    HexLogEvent("CMP01002I", "%s,category=compute,sub=evacuate,target=%s",
                CliEventAttrs().c_str(), hostname.c_str());

    return CLI_SUCCESS;
}

static int
ResetMain(int argc, const char** argv)
{
    /*
     * [0]="reset", [1]=<instance ids|all>
     */
    std::string uuid;
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    } else if (argc == 2 && strcmp(argv[1], "all") == 0) {
        uuid = HexUtilPOpen(HEX_SDK " os_nova_non_active_server_list | tail -1");
    } else {
        int index;

        std::string optCmd = HEX_SDK " os_nova_non_active_server_list";
        std::string descCmd = HEX_SDK " -v os_nova_non_active_server_list";

        if(CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid, "Select an instance to be reset: ") != CLI_SUCCESS) {
            CliPrintf("instance name is missing or not found");
            return CLI_INVALID_ARGS;
        }
    }

    HexSystemF(0, HEX_SDK " os_nova_instance_reset %s", uuid.c_str());

    CliPrintf("Confirm to hard reboot instances.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSystemF(0, HEX_SDK " os_nova_instance_hardreboot %s", uuid.c_str());

    return CLI_SUCCESS;
}

static int
ResetPassMain(int argc, const char** argv)
{
    /*
     * [0]="reset_pass", [1]=<instance id>
     */
    std::string uuid;
    std::string username, pass;
    int index;

    std::string optCmd = HEX_SDK " os_nova_server_list";
    std::string descCmd = HEX_SDK " -v os_nova_server_list";

    if(CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid, "Select an instance to reset pass: ") != CLI_SUCCESS) {
        CliPrintf("instance name/id is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, LABEL_USER_NAME, &username) || username.length() == 0) {
        CliPrint("Username is missing");
        return CLI_INVALID_ARGS;
    }
    if (!CliReadInputStr(argc, argv, 3, LABEL_PASS, &pass) || pass.length() == 0) {
        CliPrint("Password/SSH key is missing");
        return CLI_INVALID_ARGS;
    }
    HexSystemF(0, HEX_SDK " os_nova_instance_reset_pass %s %s %s", uuid.c_str(), username.c_str(), pass.c_str());

    return CLI_SUCCESS;
}

static int
FsckMain(int argc, const char** argv)
{
    /*
     * [0]="fsck", [1]=<instance id>
     */
    std::string uuid;
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    } else {
        int index;

        std::string optCmd = HEX_SDK " os_nova_server_list";
        std::string descCmd = HEX_SDK " -v os_nova_server_list";

        if(CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid, "Select an instance to be reset: ") != CLI_SUCCESS) {
            CliPrintf("instance name is missing or not found");
            return CLI_INVALID_ARGS;
        }
    }

    CliPrintf("Confirm to fsck instance filesystems (It's recommended to first shutdown instance).");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSystemF(0, HEX_SDK " ceph_rbd_fsck %s", uuid.c_str());

    return CLI_SUCCESS;
}

static int
GpuInstanceMigrateMain(int argc, const char** argv)
{
    /*
     * [0]="gpu_instance_migrate", [1]=<instance id>, [2]=<resource provider id>
     */
    if (argc < 1)
        return CLI_INVALID_ARGS;

    std::string uuid, rpid;
    int index;

    std::string optCmd = HEX_SDK " os_nova_gpu_server_list";
    std::string descCmd = HEX_SDK " -v os_nova_gpu_server_list";

    if(CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid, "Select a GPU instance to migrate: ") != CLI_SUCCESS) {
        CliPrintf("instance name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    optCmd = HEX_SDK " os_nova_pgpu_host_list_by_instance_id " + uuid;
    descCmd = HEX_SDK " -v os_nova_pgpu_host_list_by_instance_id " + uuid;
    if(CliMatchCmdDescHelper(argc, argv, 2, optCmd, descCmd, &index, &rpid, "Select a compute node: ") != CLI_SUCCESS) {
        CliPrintf("resource provider is missing or not found");
        return CLI_INVALID_ARGS;
    }

    HexSystemF(0, HEX_SDK " os_instance_pgpu_migrate %s %s", uuid.c_str(), rpid.c_str());

    return CLI_SUCCESS;
}

static int
InstanceHaConfigureMain(int argc, const char** argv)
{
    /*
     * [0]="configure", [1]=<add/delete>, [2]=<segment_name>, [3]=<host1,host2,...>
     */
    if (argc > 4)
        return CLI_INVALID_ARGS;

    int actIdx;
    std::string action;
    CliList actions;

    enum {
        ACTION_ADD = 0,
        ACTION_DELETE
    };

    actions.push_back("add");
    actions.push_back("delete");

    if(CliMatchListHelper(argc, argv, 1, actions, &actIdx, &action) != 0) {
        CliPrint("action type <add|delete> is missing or invalid");
        return false;
    }

    if (actIdx == ACTION_ADD) {
        std::string segment, hostgroup;

        if (!CliReadInputStr(argc, argv, 2, LABEL_SEG_NAME, &segment) ||
            segment.length() == 0) {
            CliPrint("segment name is missing");
            return CLI_INVALID_ARGS;
        }

        CliList seglist;
        std::string cmd = HEX_SDK " os_segment_name_list";
        if (CliPopulateList(seglist, cmd.c_str()) != 0) {
            return CLI_UNEXPECTED_ERROR;
        }

        auto it = std::find(seglist.begin(), seglist.end(), segment);
        if (it != seglist.end()) {
            CliPrint("existing segment name");
            return CLI_INVALID_ARGS;
        }

        if (!CliReadInputStr(argc, argv, 3, LABEL_HOST_LIST, &hostgroup) ||
            hostgroup.length() == 0) {
            CliPrint("host group is missing");
            return CLI_INVALID_ARGS;
        }

        // todo: validate hostgroup

        HexSpawn(0, HEX_SDK, "os_segment_add", segment.c_str(), hostgroup.c_str(), NULL);

        HexLogEvent("CMP02001I", "%s,category=compute,sub=ha,segment=%s",
                                 CliEventAttrs().c_str(), segment.c_str());
    }
    else if (actIdx == ACTION_DELETE) {
        int index;
        std::string segment;

        std::string cmd = HEX_SDK " os_segment_name_list";
        if(CliMatchCmdHelper(argc, argv, 2, cmd, &index, &segment) != CLI_SUCCESS) {
            CliPrintf("segment name is missing or not found");
            return CLI_INVALID_ARGS;
        }

        HexSpawn(0, HEX_SDK, "os_segment_delete", segment.c_str(), NULL);

        HexLogEvent("CMP02002I", "%s,category=compute,sub=ha,segment=%s",
                                 CliEventAttrs().c_str(), segment.c_str());
    }

    return CLI_SUCCESS;
}

static int
InstanceHaListMain(int argc, const char** argv)
{
    /*
     * [0]="list"
     */
    if (argc > 1)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "os_segment_list", NULL);

    return CLI_SUCCESS;
}

static int
InstanceHaShowMain(int argc, const char** argv)
{
    /*
     * [0]="show", [1]=<segment_name>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    int index;
    std::string segment;

    std::string cmd = HEX_SDK " os_segment_name_list";
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &segment) != CLI_SUCCESS) {
        CliPrintf("segment name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_segment_show", segment.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
InstanceHaJobListMain(int argc, const char** argv)
{
    /*
     * [0]="status"
     */
    if (argc > 1)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "os_masakari_job_list", NULL);

    return CLI_SUCCESS;
}

static int
InstanceHaSetProductionMain(int argc, const char** argv)
{
    /*
     * [0]="set_production", [1]=<segment>, [2]=<hostname>
     */
    if (argc > 3)
        return CLI_INVALID_ARGS;

    int index;
    std::string segment;
    std::string hostname;

    std::string cmd = HEX_SDK " os_segment_name_list";
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &segment) != CLI_SUCCESS) {
        CliPrintf("segment name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_maintenance_name_list " + segment;
    if(CliMatchCmdHelper(argc, argv, 2, cmd, &index, &hostname) != CLI_SUCCESS) {
        CliPrintf("hostname is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSpawn(0, HEX_SDK, "os_compute_node_production_set", segment.c_str(), hostname.c_str(), NULL);

    HexLogEvent("CMP02003I", "%s,category=compute,sub=ha,segment=%s,hostname=%s",
                             CliEventAttrs().c_str(), segment.c_str(), hostname.c_str());

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE("iaas", "compute",
    "Work with the IaaS compute instance settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("compute", "pre_failure_host_evacuation", PreFailureHostEvacuationMain, NULL,
        "Live evacuate instances for specified alive host to another nodes.",
        "pre_failure_host_evacuation [<hostname>]");

CLI_MODE_COMMAND("compute", "upgrade_host_evacuation", PreFailureHostEvacuationMain, NULL,
        "Live evacuate instances for specified alive host to another nodes in system upgrade.",
        "upgrade_host_evacuation [<hostname>]");

CLI_MODE_COMMAND("compute", "post_failure_host_evacuation", PostFailureHostEvacuationMain, NULL,
        "Evacuate instances for specified failed host to another nodes.",
        "post_failure_host_evacuation [<hostname>]");

CLI_MODE_COMMAND("compute", "reset", ResetMain, NULL,
        "Reset compute instance state to active and hard reboot).",
        "reset [<instance id|all>]");

CLI_MODE_COMMAND("compute", "reset_pass", ResetPassMain, NULL,
        "Reset instance login password or SSH public key).",
        "reset_pass [<instance id>]");

CLI_MODE_COMMAND("compute", "fsck", FsckMain, NULL,
        "Check and repair Filesystem of compute instances).",
        "fsck [<instance id>]");

CLI_MODE_COMMAND("compute", "gpu_instance_migrate", GpuInstanceMigrateMain, NULL,
        "Migrate a GPU instance to another host.",
        "gpu_instance_migrate [<instance id>] [<resource provider id>]");

CLI_MODE("iaas", "instance_ha",
    "Work with the IaaS instance ha settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("instance_ha", "configure", InstanceHaConfigureMain, NULL,
        "Configure host level instance HA settings.",
        "configure [<add/delete>] [<segment_name>] [<host1,host2,...>]");

CLI_MODE_COMMAND("instance_ha", "list", InstanceHaListMain, NULL,
        "List all configured instance ha segments.",
        "list");

CLI_MODE_COMMAND("instance_ha", "show", InstanceHaShowMain, NULL,
        "Show the status of the specified segment.",
        "show [<segment_name>]");

CLI_MODE_COMMAND("instance_ha", "job_list", InstanceHaJobListMain, NULL,
        "List jobs of instance ha service.",
        "job_list");

CLI_MODE_COMMAND("instance_ha", "set_production", InstanceHaSetProductionMain, NULL,
        "Set a compute node in the specified segment back to be in production.",
        "set_production [<segment_name>] [<host_name>]");

