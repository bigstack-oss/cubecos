// CUBE SDK

#include "cli_iaas_image.hpp"

static const char* LABEL_IMAGE_NAME = "Specify image name: ";
static const char* LABEL_METADATA_VAL = "Input metadata value: ";

static int
ImageImportMain(int argc, const char** argv)
{
    /* [0]="import|ide_import|lb_import|fs_import|deploy_kernel_import|deploy_initramfs_import",
     * [1]=<usb|local>, [2]=<file name>, [3]=<image name>
     * [4]=<domain>, [5]=<tenant>, [6]=<from Bigstack|from another hypervisor>
     * [7]=<public|private> [8]=<storage_backend> [9]=<os>
     */
    if (argc > 10)
        return CLI_INVALID_ARGS;

    int type, index;
    std::string media, dir, file, name, domain, tenant, visibility, pool;
    std::string flags, source, destination, os;

    bool isExtPack = false;
    bool isLbImg = false;
    bool isFsImg = false;
    bool isDeployKernel = false;
    bool isDeployInitrd = false;

    if (strcmp(argv[0], "import_extpack") == 0)
        isExtPack = true;
    if (strcmp(argv[0], "import_lb") == 0)
        isLbImg = true;
    if (strcmp(argv[0], "import_fs") == 0)
        isFsImg = true;
    if (strcmp(argv[0], "import_deploy_kernel") == 0)
        isDeployKernel = true;
    if (strcmp(argv[0], "import_deploy_initramfs") == 0)
        isDeployInitrd = true;

    if (CliMatchCmdHelper(argc, argv, 1, "echo 'usb\nlocal'", &type, &media) != CLI_SUCCESS) {
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

        HexUtilSystemF(0, 0, HEX_SDK " os_extpack_image_mount %s", USB_MNT_DIR);
    } else if (type == 1 /* local */) {
        dir = CEPHFS_GLANCE_DIR;
        HexUtilSystemF(0, 0, HEX_SDK " os_extpack_image_mount %s", CEPHFS_GLANCE_DIR);
    }

    std::string cmd = HEX_SDK " os_image_import_list " + dir;
    if (isLbImg)
        cmd += " amphora-";
    else if (isFsImg)
        cmd += " manila-";
    else if (isDeployKernel)
        cmd += " ipa-kernel-";
    else if (isDeployInitrd)
        cmd += " ipa-initramfs-";
    else if (isExtPack)
        cmd = HEX_SDK " os_image_import_extpack_list " + dir;

    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &file) != CLI_SUCCESS) {
        CliPrintf("no matched file under %s", dir.c_str());
        return CLI_INVALID_ARGS;
    }

    if (!isExtPack && !isLbImg && !isFsImg && !isDeployKernel && !isDeployInitrd) {
        if (!CliReadInputStr(argc, argv, 3, LABEL_IMAGE_NAME, &name)) {
            CliPrint("image name is required");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " os_list_domain_basic | awk '{print tolower($0)}'";
        if (CliMatchCmdHelper(argc, argv, 4, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
            CliPrintf("Invalid domain");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
        if (CliMatchCmdHelper(argc, argv, 5, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
            CliPrintf("Invalid tenant");
            return CLI_INVALID_ARGS;
        }

        if (CliMatchCmdHelper(argc, argv, 6, "echo 'from Bigstack\nfrom another hypervisor'", &index, &source, "Image source: ") != CLI_SUCCESS) {
            CliPrintf("Invalid image source");
            return CLI_INVALID_ARGS;
        }

        flags = "--os-project-domain-name " + domain + " --os-project-name " + tenant;
        if (strcmp(source.c_str(), "from Bigstack") == 0) {
            if (CliMatchCmdHelper(argc, argv, 7, "echo 'public\nprivate'", &index, &visibility, "Visibility: ") != CLI_SUCCESS) {
                CliPrintf("Unknown visibility");
                return CLI_INVALID_ARGS;
            }
            pool = "glance-images";
            flags += " --visibility " + visibility;
        } else {
            pool = "cinder-volumes";
        }

        cmd = "openstack volume type list -f value -c Name  | grep -v __DEFAULT__";
        if (CliMatchCmdHelper(argc, argv, 8, cmd, &index, &destination, "Select storage destination (volume type): ") != CLI_SUCCESS) {
            CliPrintf("Invalid storage destination");
            return CLI_INVALID_ARGS;
        }
        cmd = HEX_SDK " os_get_image_oses";
        if (CliMatchCmdHelper(argc, argv, 9, cmd, &index, &os, "Select OS (big impacts to performance if it's windows): ") != CLI_SUCCESS) {
            CliPrintf("Invalid OS");
            return CLI_INVALID_ARGS;
        }
    }

    CliPrintf("Importing...");
    int ret = 0;

    if (isFsImg)
        ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_manila_image_import", dir.c_str(), file.c_str(), NULL);
    else if (isLbImg)
        ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_octavia_image_import", dir.c_str(), file.c_str(), NULL);
    else if (isDeployKernel)
        ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_ironic_deploy_kernel_import", dir.c_str(), file.c_str(), NULL);
    else if (isDeployInitrd)
        ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_ironic_deploy_initramfs_import", dir.c_str(), file.c_str(), NULL);
    else if (isExtPack)
        ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_extpack_image_import", dir.c_str(), file.c_str(), NULL);
    else
        ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
            HEX_SDK, "os_image_import",
            dir.c_str(), file.c_str(), name.c_str(),
            flags.c_str(), pool.c_str(), destination.c_str(), os.c_str(), NULL);

    if (type == 0 /* usb */) {
        HexUtilSystemF(0, 0, HEX_SDK " os_extpack_image_umount %s", USB_MNT_DIR);
        if (ret != 0)
            CliPrintf("Importing failed. Please check the USB drive and retry the command.");
        else
            CliPrintf("Importing %s complete. It is safe to remove the USB drive.", name.c_str());
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    } else if (type == 1 /* local */) {
        HexUtilSystemF(0, 0, HEX_SDK " os_extpack_image_umount %s", CEPHFS_GLANCE_DIR);
        if (ret != 0)
            CliPrintf("Importing failed. Please check the local drive and retry the command.");
        else
            CliPrintf("Importing %s complete. It is safe to remove the local image file.", name.c_str());
    }

    return CLI_SUCCESS;
}

static int
InstanceExportMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="export_instance" [1]="domain" [2]="tenant" [3]="instance" [4]="media" [5]="format"*/)
        return CLI_INVALID_ARGS;

    int type, index;
    std::string domain, tenant, instanceId, agent, media, dir, format;
    std::string cmd, descCmd;

    cmd = std::string(HEX_SDK) + " os_list_domain_basic | awk '{print tolower($0)}'";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_instance_id_list " + tenant;
    descCmd = std::string(HEX_SDK) + " -v os_instance_id_list " + tenant;
    if (CliMatchCmdDescHelper(argc, argv, 3, cmd, descCmd, &index, &instanceId, "Select instance ID: ") != CLI_SUCCESS) {
        CliPrintf("Invalid instance");
        return CLI_INVALID_ARGS;
    }

    CliPrintf("Is the instance installed apt - qemu-guest-agent?");
    CliPrintf("Is a requirement for this operation");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    if (CliMatchCmdHelper(argc, argv, 4, "echo 'vmdk\nraw'", &index, &format, "Select output format: ") != CLI_SUCCESS) {
        CliPrintf("Unknown file format");
        return CLI_INVALID_ARGS;
    }

    if (CliMatchCmdHelper(argc, argv, 5, "echo 'usb\nlocal'", &type, &media, "Select output destination: ") != CLI_SUCCESS) {
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
    } else if (type == 1 /* local */) {
        dir = CEPHFS_GLANCE_DIR;
    }

    int ret = HexSpawn(0, HEX_SDK, "os_instance_export", tenant.c_str(), instanceId.c_str(), dir.c_str(), format.c_str(), NULL);

    if (type == 0 /* usb */) {
        if (ret != 0)
            CliPrintf("Exporting failed. Please check the USB drive and retry the command.");
        else
            CliPrintf("Exporting %s complete. It is safe to remove the USB drive.", instanceId.c_str());
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    } else if (type == 1 /* local */) {
        if (ret != 0)
            CliPrintf("Exporting failed. Please check the local drive and retry the command.");
        else
            CliPrintf("Exporting %s complete. It is safe to remove the local image file.", instanceId.c_str());
    }

    return CLI_SUCCESS;
}

static int
MetadataMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="volume_id" [1]="metadata_key" [2]="metadata_value"*/)
        return CLI_INVALID_ARGS;

    int index;
    std::string vol_id, metadata_key, metadata_val;
    std::string cmd, descCmd;

    cmd = std::string(HEX_SDK) + " os_volume_image_list";
    descCmd = std::string(HEX_SDK) + " -v os_volume_image_list";
    if (CliMatchCmdDescHelper(argc, argv, 1, cmd, descCmd, &index, &vol_id, "Select volume ID: ") != CLI_SUCCESS) {
        CliPrintf("Invalid instance");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_volume_image_metadata " + vol_id.c_str();
    descCmd = std::string(HEX_SDK) + " -v os_volume_image_metadata " + vol_id.c_str();
    if (CliMatchCmdDescHelper(argc, argv, 2, cmd, descCmd, &index, &metadata_key, "Select a metadata key:value to change: ") != CLI_SUCCESS) {
        CliPrintf("Invalid metadata_key/val");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, LABEL_METADATA_VAL, &metadata_val) || metadata_val.length() == 0) {
        CliPrint("Metadata value is missing");
        return CLI_INVALID_ARGS;
    }

    HexUtilSystemF(0, 0, HEX_SDK " os_volume_image_metadata %s %s %s", vol_id.c_str(), metadata_key.c_str(), metadata_val.c_str());

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_COMMAND_IAAS, "image",
    "Work with cube images. Please upload images to " CEPHFS_GLANCE_DIR " for local import.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("image", "metadata", MetadataMain, NULL,
    "set Cinder volume metadata.",
    "metadata <domain> <tenant>");

CLI_MODE_COMMAND("image", "import", ImageImportMain, NULL,
    "import image from usb or local store folder.",
    "import <usb|local> <file_name> <image_name> <domain> <tenant> <from Bigstack|from another hypervisor> <public|private> <storage_backend> <os>");

CLI_MODE_COMMAND("image", "import_extpack", ImageImportMain, NULL,
    "import extension pack images from usb or local store folder.",
    "import_extpack <usb|local> <file_name>");

CLI_MODE_COMMAND("image", "import_lb", ImageImportMain, NULL,
    "import load-balancer image from usb or local store folder.",
    "import_lb <usb|local> <file_name>");

CLI_MODE_COMMAND("image", "import_fs", ImageImportMain, NULL,
    "import file storage image from usb or local store folder.",
    "import_fs <usb|local> <file_name>");

CLI_MODE_COMMAND("image", "import_deploy_kernel", ImageImportMain, NULL,
    "import baremetal deploy kernel from usb or local store folder.",
    "import_deploy_kernel <usb|local> <file_name>");

CLI_MODE_COMMAND("image", "import_deploy_initramfs", ImageImportMain, NULL,
    "import baremetal deploy initramfs from usb or local store folder.",
    "import_deploy_initramfs <usb|local> <file_name>");

CLI_MODE_COMMAND("image", "export_instance", InstanceExportMain, NULL,
    "export instance disks as vmdk to usb drive.",
    "export_instance <usb> <file_name>");
