// HEX SDK

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#define ISO_MNT_DIR "/mnt/iso"
#define STORE_DIR "/var/support"

static int
LicenseCheckMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="check" */)
        return CLI_INVALID_ARGS;

    CliPrintf("\n====== CubeCOS ======\n");
    HexSpawn(0, HEX_SDK, "license_cluster_check", NULL);

    CliPrintf("\n====== CubeCMP ======\n");
    HexSpawn(0, HEX_SDK, "license_cluster_check", "cmp", NULL);

    return CLI_SUCCESS;
}

static int
LicenseShowMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="show" */)
        return CLI_INVALID_ARGS;

    CliPrintf("\n====== CubeCOS ======\n");
    HexSpawn(0, HEX_SDK, "license_cluster_show", NULL);

    CliPrintf("\n====== CubeCMP ======\n");
    HexSpawn(0, HEX_SDK, "license_cluster_show", "cmp", NULL);

    return CLI_SUCCESS;
}

static int
LicenseImportMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="import", [1]=<usb|iso|local>, [2]=<license name> */)
        return CLI_INVALID_ARGS;

    int type, index;
    std::string media, dir, file;

    if (CliMatchCmdHelper(argc, argv, 1, "echo 'usb\niso\nlocal'", &type, &media) != CLI_SUCCESS) {
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
    } else if (type == 1 /* iso */) {
        dir = ISO_MNT_DIR;
        CliPrintf("Insert an ISO via virtual media or CDROM on the appliance.");
        if (!CliReadConfirmation())
            return CLI_SUCCESS;

        AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
        if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_iso", NULL) != 0) {
            CliPrintf("Could not mount the ISO drive. Please check the ISO/CDROM drive and retry the command.\n");
            return CLI_SUCCESS;
        }
    } else if (type == 2 /* local */) {
        dir = STORE_DIR;
    }

    std::string cmd = HEX_SDK " license_import_list " + dir;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &file) != CLI_SUCCESS) {
        CliPrintf("no matched file under %s", dir.c_str());
        return CLI_INVALID_ARGS;
    }

    int ret;

    ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
                        HEX_SDK, "license_cluster_import_check", dir.c_str(), file.c_str(), NULL);

    // FIXME: -1  (65280) = (65536 - 256),
    //        -2  (65024) = (65536 - 512),
    //        ...
    //        -10 (62976) = (65536 - 2560)
    if (ret > 62900) {
        CliPrintf("\nThis is NOT a valid license!");
        return CLI_SUCCESS;
    }

    CliPrintf("\nInstalling the license?");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    CliPrintf("Importing...");

    ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
                        HEX_SDK, "license_cluster_import", dir.c_str(), file.c_str(), NULL);


    if (type == 0 /* usb */) {
        if (ret != 0)
            CliPrintf("Importing failed. Please check the USB drive and retry the command.");
        else
            CliPrintf("Importing %s complete. It is safe to remove the USB drive.", file.c_str());
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    } else if (type == 1 /* iso */) {
        if (ret != 0)
            CliPrintf("Importing failed. Please check the ISO/CDROM drive and retry the command.");
        else
            CliPrintf("Importing %s complete. It is safe to remove the ISO/CDROM drive.", file.c_str());
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_iso", NULL);
    } else if (type == 2 /* local */) {
        if (ret != 0)
            CliPrintf("Importing failed. Please check the local drive and retry the command.");
        else
            CliPrintf("Importing %s complete. It is safe to remove the local license file.", file.c_str());
    }

    return CLI_SUCCESS;
}

static int
LicenseSerialMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="hardware_serial" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "license_cluster_serial_get", NULL);

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "license",
         "Work with license settings. please upload images to " STORE_DIR " for local import.",
         !HexStrictIsErrorState());

CLI_MODE_COMMAND("license", "check", LicenseCheckMain, NULL,
    "Check license immediately.",
    "check");

CLI_MODE_COMMAND("license", "show", LicenseShowMain, NULL,
    "Display the current information in license file.",
    "show");

CLI_MODE_COMMAND("license", "import", LicenseImportMain, NULL,
    "Import a license to the cluster.",
    "import <usb|iso|local> <license name>(.license)");

CLI_MODE_COMMAND("license", "hardware_serial", LicenseSerialMain, NULL,
    "List hardware serials of the cluster.",
    "hardware_serial");

