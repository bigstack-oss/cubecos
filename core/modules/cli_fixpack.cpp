// CUBE SDK

#include <hex/config_module.h>  // CONFIG_EXIT_NEED_REBOOT, ...
#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <sstream>

#define STORE_DIR "/var/fixpack"

static int
GetFixpackHistoryList(CliList& list)
{
    int ret = CliPopulateList(list, "/usr/sbin/hex_config fixpack_get_history");
    if (ret != 0) {
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

static bool
DisplayFixpackHistoryList()
{
    CliList list;
    size_t pos;
    if (GetFixpackHistoryList(list) != CLI_SUCCESS)
        return false;

    if (list.size() == 0) {
        CliPrintf("No fixpack history exists.");
    }
    else {
        CliPrintf("Fix Packs History:");
        printf("%-21.21s %-10.10s %-15.15s %-12.12s %-8.8s %s\n", "Date", "Id", "Title", "Action", "Rollback", "Description" );
        for (size_t i = 0; i < list.size(); ++i) {
            std::string temp(list[i]);

            pos = temp.find_last_of("|");
            std::string date_epoch = temp.substr(pos + 1);
            temp.erase(pos);

            pos = temp.find_last_of("|");
            std::string desc = temp.substr(pos + 1);
            temp.erase(pos);

            pos = temp.find_last_of("|");
            std::string action = temp.substr(pos + 1);
            temp.erase(pos);

            pos = temp.find_last_of("|");
            std::string rollback = temp.substr(pos + 1);
            temp.erase(pos);

            pos = temp.find_last_of("|");
            std::string name = temp.substr(pos + 1);
            temp.erase(pos);

            pos = temp.find_last_of("|");
            std::string id = temp.substr(pos + 1);
            temp.erase(pos);
            std::string date = temp;

            // don't show any rollback status if the fixpack is already uninstalled
            if (action.compare(0, 9, "Uninstall") == 0 )
                rollback.clear();

            printf("%-21.21s %-10.10s %-15.15s %-12.12s %-8.8s %s\n", date.c_str(), id.c_str(), name.c_str(), action.c_str(), rollback.c_str(), desc.c_str());
        }
    }
    return true;
}

static int
HistoryMain(int argc, const char** argv)
{
    if (argc != 1) {
        return CLI_INVALID_ARGS;
    }

    if (!DisplayFixpackHistoryList())
        return CLI_UNEXPECTED_ERROR;

    return CLI_SUCCESS;
}

static int
ListMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="list", [1]=<usb|local> */)
        return CLI_INVALID_ARGS;

    int index;
    std::string media;

    if(CliMatchCmdHelper(argc, argv, 1, "echo 'usb\nlocal'", &index, &media) != CLI_SUCCESS) {
        CliPrintf("Unknown media");
        return CLI_INVALID_ARGS;
    }

    if (index == 0 /* usb */) {
        CliPrintf("Insert a USB drive into the USB port on the appliance.");
        if (!CliReadConfirmation())
            return CLI_SUCCESS;

        AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
        if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_usb", NULL) != 0) {
            CliPrintf("Could not write to the USB drive. Please check the USB drive and retry the command.\n");
            return CLI_SUCCESS;
        }

        HexSpawn(0, HEX_SDK, "FixpackList", USB_MNT_DIR, NULL);
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    }
    else if (index == 1 /* local */) {
        HexSpawn(0, HEX_SDK, "FixpackList", STORE_DIR, NULL);
    }

    return CLI_SUCCESS;
}

// node names and fixpack ids go into commands; allow only [A-Za-z0-9._-]
static bool
IsValidName(const std::string& name)
{
    return !name.empty() && name.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_") == std::string::npos;
}

static void
UmountUsb(bool usb)
{
    if (usb)
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
}

// Install <fixpackpath> on one node; returns the hex_config exit code.
static int
InstallOnNode(const std::string& node, const std::string& fixpackpath, const std::string& fixpackname)
{
    char hostname[256] = {0};
    CliGetHostname(hostname, sizeof(hostname));

    // argv spawn, no shell; hex_config's own output streams to the terminal
    int ret;
    if (node == hostname)
        ret = HexSpawn(0, HEX_CFG, "fixpack", fixpackpath.c_str(), NULL);
    else
        ret = HexSpawn(0, HEX_SDK, "fixpack_node_install", node.c_str(), fixpackpath.c_str(), NULL);

    if ((ret & CONFIG_EXIT_FAILURE) != 0) {
        HexLogError("Installation of fixpack %s on %s has failed", fixpackname.c_str(), node.c_str());
        CliPrintf("Installation of fixpack %s on %s has failed.", fixpackname.c_str(), node.c_str());
    }
    else {
        HexLogInfo("Installation of fixpack %s on %s is successful", fixpackname.c_str(), node.c_str());
        CliPrintf("Installation of fixpack %s on %s is successful", fixpackname.c_str(), node.c_str());
    }

    return ret;
}

static int
InstallMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="install", [1]=<usb|local>, [2]=<file name>, [3]=<node,...> */)
        return CLI_INVALID_ARGS;

    int index;
    std::string media, dir, file;

    if (HexStrictIsEnabled()) {
        CliPrintf("The appliance is currently running in strict mode.\n");
        CliPrintf("Applying a fixpack that is not certified while in strict mode can invalidate the appliance certification.");
        CliPrintf("The only way to recover from strict error state is to restore the appliance from a good backup.\n");
        CliPrintf("Confirm with technical support that this fixpack is safe to install in FIPS mode before you apply it.\n");

        CliPrintf("Do you want to continue installing this fixpack?\n");
        if (!CliReadConfirmation())
            return CLI_SUCCESS;
    }

    if(CliMatchCmdHelper(argc, argv, 1, "echo 'usb\nlocal'", &index, &media) != CLI_SUCCESS) {
        CliPrintf("Unknown media");
        return CLI_INVALID_ARGS;
    }

    if (index == 0 /* usb */) {
        dir = USB_MNT_DIR;
        CliPrintf("Insert a USB drive into the USB port on the appliance.");
        if (!CliReadConfirmation())
            return CLI_SUCCESS;

        AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
        if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_usb", NULL) != 0) {
            CliPrintf("Could not write to the USB drive. Please check the USB drive and retry the command.\n");
            return CLI_SUCCESS;
        }

        if (CliMatchCmdHelper(argc, argv, 2,
                HEX_SDK " FixpackList " USB_MNT_DIR, &index, &file) != CLI_SUCCESS) {
            CliPrintf("no such file");
            return CLI_INVALID_ARGS;
        }
    }
    else if (index == 1 /* local */) {
        dir = STORE_DIR;
        if (CliMatchCmdHelper(argc, argv, 2,
                HEX_SDK " FixpackList " STORE_DIR, &index, &file) != CLI_SUCCESS) {
            CliPrintf("no matched file under %s", STORE_DIR);
            return CLI_INVALID_ARGS;
        }
    }

    std::string fixpackpath = dir;
    std::string fixpackname = file;

    fixpackpath = dir + "/" + file;

    size_t pos = fixpackname.find(".fixpack");
    if (pos != std::string::npos)
        fixpackname.erase(pos, std::string::npos);

    bool usb = (dir == USB_MNT_DIR);

    // default to the nodes that don't have this fixpack yet
    std::string nodes;
    if (argc == 4) {
        nodes = argv[3];
    }
    else {
        CliList missing;
        std::string cmd = std::string(HEX_SDK) + " fixpack_missing_nodes " + HexBuildShellArg(fixpackpath);
        if (CliPopulateList(missing, cmd.c_str()) != 0) {
            CliPrintf("Unable to read the fixpack ID of %s", fixpackname.c_str());
            UmountUsb(usb);
            return CLI_SUCCESS;
        }
        if (missing.size() == 0) {
            CliPrintf("Fixpack %s is already installed on every node.", fixpackname.c_str());
            UmountUsb(usb);
            return CLI_SUCCESS;
        }
        for (size_t i = 0; i < missing.size(); ++i)
            nodes += (i ? "," : "") + missing[i];

        std::string line;
        std::string prompt = "Nodes to install [" + nodes + "]: ";
        if (!CliReadLine(prompt.c_str(), line)) {
            UmountUsb(usb);
            return CLI_SUCCESS;
        }
        if (!line.empty())
            nodes = line;
    }

    // one node at a time
    int ret = 0;
    std::stringstream ss(nodes);
    std::string node;
    while (std::getline(ss, node, ',')) {
        if (node.empty())
            continue;
        if (!IsValidName(node)) {
            CliPrintf("Invalid node name: %s", node.c_str());
            ret |= CONFIG_EXIT_FAILURE;
            break;
        }
        int r = InstallOnNode(node, fixpackpath, fixpackname);
        ret |= r;
        if ((r & CONFIG_EXIT_FAILURE) != 0)
            break;
    }

    UmountUsb(usb);

    if ((ret & CONFIG_EXIT_NEED_REBOOT) != 0) {
        CliPrintf("fixpack requires reboot");
        CliPrintf("use reboot CLI to reboot the appliance");
    }

    return CLI_SUCCESS;
}

static int
StatusMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="status", [1]=<fixpack id> */)
        return CLI_INVALID_ARGS;

    std::string cmd = std::string(HEX_SDK) + " fixpack_status";
    if (argc == 2) {
        std::string id = argv[1];
        if (!IsValidName(id)) {
            CliPrintf("Invalid fixpack id: %s", id.c_str());
            return CLI_INVALID_ARGS;
        }
        cmd += " " + HexBuildShellArg(id);
    }

    CliList list;
    CliPopulateList(list, cmd.c_str());
    printf("%-20.20s %-30s %s\n", "Node", "Installed", "Status");
    for (size_t i = 0; i < list.size(); ++i) {
        std::stringstream ss(list[i]);
        std::string node, ids, status;
        std::getline(ss, node, '|');
        std::getline(ss, ids, '|');
        std::getline(ss, status);
        printf("%-20.20s %-30s %s\n", node.c_str(), ids.c_str(), status.c_str());
    }

    return CLI_SUCCESS;
}

static int
RollbackMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="rollback", [1]=<node,...> */)
        return CLI_INVALID_ARGS;

    // the local node's latest rollback point, else any node's
    CliList list;
    CliPopulateList(list, HEX_SDK " fixpack_rollback_id");
    if (list.size() == 0 || !IsValidName(list[0])) {
        CliPrintf("There are no available rollback points.");
        return CLI_SUCCESS;
    }
    std::string id = list[0];

    // default to the nodes whose latest rollback point is this fixpack
    std::string nodes;
    if (argc == 2) {
        nodes = argv[1];
    }
    else {
        CliList targets;
        std::string cmd = std::string(HEX_SDK) + " fixpack_rollback_nodes " + HexBuildShellArg(id);
        CliPopulateList(targets, cmd.c_str());
        if (targets.size() == 0) {
            CliPrintf("No reachable node has fixpack %s as its latest.", id.c_str());
            return CLI_SUCCESS;
        }
        for (size_t i = 0; i < targets.size(); ++i)
            nodes += (i ? "," : "") + targets[i];

        std::string line;
        std::string prompt = "Nodes to roll back " + id + " [" + nodes + "]: ";
        if (!CliReadLine(prompt.c_str(), line))
            return CLI_SUCCESS;
        if (!line.empty())
            nodes = line;
    }

    // one node at a time; each node refuses unless its latest fixpack is <id>
    int ret = 0;
    std::stringstream ss(nodes);
    std::string node;
    while (std::getline(ss, node, ',')) {
        if (node.empty())
            continue;
        if (!IsValidName(node)) {
            CliPrintf("Invalid node name: %s", node.c_str());
            break;
        }
        int r = HexSpawn(0, HEX_SDK, "fixpack_node_rollback", node.c_str(), id.c_str(), NULL);
        ret |= r;
        if ((r & CONFIG_EXIT_FAILURE) != 0) {
            HexLogError("Rollback of fixpack %s on %s has failed", id.c_str(), node.c_str());
            CliPrintf("Rollback of fixpack %s on %s has failed.", id.c_str(), node.c_str());
            break;
        }
        HexLogInfo("Rollback of fixpack %s on %s is successful", id.c_str(), node.c_str());
        CliPrintf("Rollback of fixpack %s on %s is successful", id.c_str(), node.c_str());
    }

    if ((ret & CONFIG_EXIT_NEED_REBOOT) != 0) {
        CliPrintf("fixpack requires reboot");
        CliPrintf("use reboot CLI to reboot the appliance");
    }

    return CLI_SUCCESS;
}

// This mode is not available in FIPS error state
CLI_MODE(CLI_TOP_MODE, "fixpack",
         "Work with fixpacks. please upload fixpacks to " STORE_DIR " for local installation.",
         !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("fixpack", "list", ListMain, 0,
    "List available fixpack on the inserted USB device.",
    "list");

CLI_MODE_COMMAND("fixpack", "install", InstallMain, 0,
    "Install a fixpack node by node; defaults to the nodes that don't have it yet.",
    "install <usb|local> <file> [<node>,...]");

CLI_MODE_COMMAND("fixpack", "view_history", HistoryMain, 0,
    "Display installation history for all fixpack.",
    "view_history");

CLI_MODE_COMMAND("fixpack", "status", StatusMain, 0,
    "Show the fixpacks installed on each node and which nodes are missing one.",
    "status [<fixpack id>]");

CLI_MODE_COMMAND("fixpack", "rollback", RollbackMain, 0,
    "Uninstall the most recently installed fixpack node by node; defaults to the nodes where it is the latest.",
    "rollback [<node>,...]");

