// HEX SDK

#include <unistd.h>  // gethostname()
#include <climits> // HOST_NAME_MAX

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/cli_support_helper.h>

#include <cube/cubesys.h>

static int
CreateMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    char filename[256];
    std::string list;
    FILE *fp = NULL;

    AutoSignalHandlerMgt hdr(UnInterruptibleHdr);

    if (!CliReadInputStr(argc, argv, 1, "Enter comma-separated volume ID list:", &list))
        return CLI_FAILURE;

    fp = HexPOpenF(HEX_CFG " volume_meta_create %s", list.c_str());
    if (fp != NULL) {
        if (fgets(filename, sizeof(filename), fp) == NULL) {
            HexLogError("Unable to retieve the name of the file created");
            pclose(fp);
            return CLI_UNEXPECTED_ERROR;
        }
        else if (pclose(fp) == 0) {
            char username[256];
            CliGetUserName(username, sizeof(username));
            HexLogInfo("%s created a volume metadata file %s via %s", username, filename, "CLI");
            CliPrintf("%s", filename);
        }
        else {
            HexLogError("Could not create volume metadata file");
            return CLI_UNEXPECTED_ERROR;
        }
    }
    else {
        HexLogError("Could not create volume metadata file");
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

static int
ApplyMain(int argc, const char** argv)
{
    if (argc > 4) {
        return CLI_INVALID_ARGS;
    }

    CliSupportHelper support;
    char cmd[256];
    std::string user, proj, host, filename;

    if (!CliReadInputStr(argc, argv, 1, "Enter user name: ", &user))
        return CLI_FAILURE;

    if (!CliReadInputStr(argc, argv, 2, "Enter project name: ", &proj))
        return CLI_FAILURE;

    snprintf(cmd, sizeof(cmd), HEX_CFG " volume_meta_list | sort");
    if (!support.select(cmd, support.pick(argc, argv, 3), &filename))
        return CLI_FAILURE;

    HexSpawn(0, HEX_CFG, "volume_meta_apply",
                user.c_str(), proj.c_str(),
                "cube@ceph#ceph", "CubeStorage", filename.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
ListMain(int argc, const char** argv)
{
    if (argc != 1)
        return CLI_INVALID_ARGS;

    char cmd[256];
    CliList list;
    CliSupportHelper support;

    snprintf(cmd, sizeof(cmd), HEX_CFG " volume_meta_list | sort");
    if (!support.list(cmd, &list))
        return CLI_FAILURE;

    for (size_t i = 0; i < list.size(); ++i)
        CliPrintf("%zu: %s", i + 1, list[i].c_str());

    return CLI_SUCCESS;
}

static int
DeleteMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    char cmd[256];
    CliSupportHelper support;
    std::string filename;

    snprintf(cmd, sizeof(cmd), HEX_CFG " volume_meta_list | sort");
    if (!support.select(cmd, support.pick(argc, argv, 1), &filename))
        return CLI_FAILURE;

    AutoSignalHandlerMgt hdr(UnInterruptibleHdr);
    if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
                      HEX_CFG, "volume_meta_delete",
                      filename.c_str(), NULL) == 0) {
        CliPrintf("Volume meta file %s deleted", filename.c_str());

        // char username[256];
        // CliGetUserName(username, sizeof(username));
        // HexLogEvent("User [username] successfully delete [filename] via [CLI]");
    }
    else {
        HexLogError("Could not delete volume meta file: %s", filename.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

static int
DownloadMain(int argc, const char** argv)
{
    if (argc > 2)
        return CLI_INVALID_ARGS;

    char cmd[256];
    CliSupportHelper support;
    std::string filename;

    snprintf(cmd, sizeof(cmd), HEX_CFG " volume_meta_list | sort");
    if (!support.select(cmd, support.pick(argc, argv, 1), &filename))
        return CLI_FAILURE;

    if (!support.download(filename))
        return CLI_FAILURE;

    return CLI_SUCCESS;
}

static int
UploadMain(int argc, const char** argv)
{
    if (argc > 1)
        return CLI_INVALID_ARGS;

    CliSupportHelper support;
    if (!support.upload("volume-meta"))
        return CLI_FAILURE;

    return CLI_SUCCESS;
}

// This mode is not available in strict error state
CLI_MODE(CLI_TOP_MODE, "volume_meta",
    "Work with volume meta files.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("volume_meta", "create", CreateMain, 0,
    "Create a snapshot of current policy files.",
    "create <comma-separated volume id list>");

CLI_MODE_COMMAND("volume_meta", "apply", ApplyMain, 0,
   "Apply volume metadata file by giving project and user ID.",
   "apply [<user_name>] [<project_name>] [<file_index>] [<hostname>]");

CLI_MODE_COMMAND("volume_meta", "list", ListMain, 0,
    "List the volume meta files.",
    "list");

CLI_MODE_COMMAND("volume_meta", "delete", DeleteMain, 0,
    "Delete a volume meta file.",
    "delete [<index>]");

CLI_MODE_COMMAND("volume_meta", "download", DownloadMain, 0,
    "Download a volume metadata file to a USB flash drive.",
    "download [<file_index>]");

CLI_MODE_COMMAND("volume_meta", "upload", UploadMain, 0,
    "Upload a volume metadata file from a USB flash drive.",
    "upload");

