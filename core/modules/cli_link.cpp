// HEX SDK

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>
#include <hex/process_util.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#define STORE_DIR "/var/support"

static int
PickUploadFile(int argc, const char** argv, std::string *name)
{
    int type, index;
    std::string media, dir, file;

    if(CliMatchCmdHelper(argc, argv, 1, "echo 'usb\nlocal'", &type, &media) != CLI_SUCCESS) {
        CliPrintf("Unknown media");
        return CLI_INVALID_ARGS;
    }

    if (type == 0 /* usb */) {
        dir = USB_MNT_DIR;
        CliPrintf("Insert a USB drive into the USB port on the appliance.");
        if (!CliReadConfirmation())
            return CLI_SUCCESS;

        AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
        if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_usb", NULL) != 0) {
            CliPrintf("Could not write to the USB drive. Please check the USB drive and retry the command.\n");
            return CLI_SUCCESS;
        }
    }
    else if (type == 1 /* local */) {
        dir = STORE_DIR;
    }

    // list files not dir
    std::string cmd = "ls -p " + dir + " | grep -v /";
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &file) != CLI_SUCCESS) {
        CliPrintf("no such file");
        return false;
    }

    *name = dir + "/" + file;

    return CLI_SUCCESS;
}

static int
DeviceImportMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="device_import", [1]=<usb|local>, [2]=<file name> */)
        return CLI_INVALID_ARGS;

    std::string name;

    int ret = PickUploadFile(argc, argv, &name);
    if (ret != CLI_SUCCESS)
        return ret;

    CliPrintf("Importing...");
    HexUtilSystemF(0, 0, HEX_SDK " network_device_link %s", name.c_str());

    return CLI_SUCCESS;
}

static int
DevAgentCfgMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="device_agent_config", [1]=<linux|windows> */)
        return CLI_INVALID_ARGS;

    int index;
    std::string type;

    if(CliMatchCmdHelper(argc, argv, 1, "echo 'linux\nwindows'", &index, &type) != CLI_SUCCESS) {
        CliPrintf("Unknown operation system type");
        return CLI_INVALID_ARGS;
    }

    if (index == 0 /* linux */)
        HexSystem(0, HEX_CFG, "get_linux_agent_config", NULL);
    else if (index == 1 /* windows */)
        HexSystem(0, HEX_CFG, "get_win_agent_config", NULL);

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "link",
         "Work with link settings.",
         !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("link", "device_import", DeviceImportMain, NULL,
    "Import device list from usb or local\n"
    "please upload file to " STORE_DIR " for local import.",
    "device_import <usb|local> <file_name>\n"
    "line format: \n"
    "  vendor=<dell|hp|advantech>,proto=<lan|lanplus>,ip=<IPADDR>,\n"
    "  user=<USERNAME>,pass=<PASSWORD>(,role=cube,hostanme=<HOST>,ping=<IPADDR>)");

CLI_MODE_COMMAND("link", "device_agent_config", DevAgentCfgMain, NULL,
    "Display device agent config.",
    "device_agent_config <linux|windows>");

