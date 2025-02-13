// HEX SDK

#include <hex/config_module.h>  // CONFIG_EXIT_NEED_REBOOT, ...
#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>

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

static int
InstallMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="install", [1]=<usb|local>, [2]=<file name> */)
        return CLI_INVALID_ARGS;

    int index;
    std::string media, dir, file, msg;

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

    std::string hostname = HexUtilPOpen("hostname | tr -d '\n'");
    std::string sync_fixpack = " cube_cluster_run all rsync -a root@" + hostname + ":" + fixpackpath + " " + fixpackpath;
    HexSpawn(0, HEX_SDK, sync_fixpack.c_str(), NULL);

    size_t pos = fixpackname.find(".fixpack");
    if (pos != std::string::npos)
        fixpackname.erase(pos, std::string::npos);

    std::string cmd = std::string(HEX_SDK) + " cube_cluster_run all " + std::string(HEX_CFG) + " fixpack " + fixpackpath;

    CliList list;
    int ret = CliPopulateList(list, cmd.c_str());
    if ((ret & CONFIG_EXIT_FAILURE) != 0) {
        index = list.size() - 1;
        if ( index < 0 ) {
            msg = "Unknown problem has occurred";
        } else {
            msg = list[index];
        }
        HexLogError("Installation of fixpack %s has failed with error: %s", fixpackname.c_str(), msg.c_str());
        CliPrintf("Installation of fixpack %s has failed.", fixpackname.c_str());
        CliPrintf("Error: %s", msg.c_str());
        // TODO HexLogEvent("interface=cli,user=%s", userName.c_str());
    }
    else {
        HexLogInfo("Installation of fixpack %s is successful", fixpackname.c_str());
        CliPrintf("Installation of fixpack %s is successful", fixpackname.c_str());
        // TODO HexLogEvent("interface=cli,user=%s", userName.c_str());
    }

    if (index == 0 /* usb */)
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);

    if ((ret & CONFIG_EXIT_NEED_REBOOT) != 0) {
        CliPrintf("fixpack requires reboot");
        CliPrintf("use reboot CLI to reboot the appliance");
    }
    else if ((ret & CONFIG_EXIT_NEED_LMI_RESTART) != 0) {
        CliPrintf("fixpack requires LMI restart");
        CliPrintf("Restarting LMI... ");
        HexSpawn(0, "/usr/sbin/hex_config", "restart_lmi", NULL);
        CliPrintf("Done");
    }

    return CLI_SUCCESS;
}

static int RollbackMain(int argc, const char** argv)
{
    if (argc != 1) {
        return CLI_INVALID_ARGS;
    }

    std::string cmd = " cube_cluster_run all " + std::string(HEX_CFG) + " fixpack_rollback";
    int ret = HexSpawn(0, HEX_SDK, cmd.c_str(), NULL);
   
    if ((ret & CONFIG_EXIT_NEED_REBOOT) != 0) {
        CliPrintf("fixpack requires reboot");
        CliPrintf("use reboot CLI to reboot the appliance");
    }
    else if ((ret & CONFIG_EXIT_NEED_LMI_RESTART) != 0) {
        CliPrintf("fixpack requires LMI restart");
        CliPrintf("Restarting LMI... ");
        HexSpawn(0, "/usr/sbin/hex_config", "restart_lmi", NULL);
        CliPrintf("Done");
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
    "Install available fixpack on the inserted USB device.",
    "install");

CLI_MODE_COMMAND("fixpack", "view_history", HistoryMain, 0,
    "Display installation history for all fixpack.",
    "view_history");

CLI_MODE_COMMAND("fixpack", "rollback", RollbackMain, 0,
    "Uninstall most recently installed fixpack.",
    "rollback");

