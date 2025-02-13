// HEX SDK

#include <sstream>

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/process_util.h>

#include <cube/cubesys.h>

#define CEPHFS_K8S_DIR "/mnt/cephfs/k8s"

#define CUBECTL_BIN "/usr/local/bin/cubectl"
#define RANCHER_BIN "/usr/local/bin/rancher"

#define APPLIANCE_DB_DIR "/var/appliance-db"

static int
ImgImportMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="image_import", [1]=<usb|local>, [2]=<file name> */)
        return CLI_INVALID_ARGS;

    int type, index;
    std::string media, dir, file, name;

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
        dir = CEPHFS_K8S_DIR;
    }

    std::string cmd = "find " + dir + " -name 'k8s-*.tar'";
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &file) != CLI_SUCCESS) {
        CliPrintf("No such image file");
        return CLI_INVALID_ARGS;
    }

    int ret = 0;
    ret = HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0,
        CUBECTL_BIN, "config", "docker", "import-registry", file.c_str(), NULL);

    if (type == 0 /* usb */) {
        CliPrintf("Please remove the USB drive.");
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    }

    if (ret != 0) {
        CliPrintf("Import failed. Please check the USB/local drive and retry the command.");
        return CLI_FAILURE;
    }


    return CLI_SUCCESS;
}

static int
ImgCheckMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="image_check" */)
        return CLI_INVALID_ARGS;

    if (HexSystemF(0, "cubectl config docker check-image /opt/rancher/rancher-images.txt") != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
NodeAddMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="node_add", [1]=<cluster name>, [2]=<node name> , [3]=<role opts>*/)
        return CLI_INVALID_ARGS;

    int index;
    std::string clusterName;
    if (CliMatchCmdHelper(argc, argv, 1, "sudo " RANCHER_BIN " context switch <<< 1 >/dev/null 2>&1 && sudo " RANCHER_BIN " cluster ls --format {{.Cluster.Name}} 2>/dev/null", &index, &clusterName) != CLI_SUCCESS) {
        CliPrintf("No kubernetes cluster");
        return CLI_INVALID_ARGS;
    }

    //CliPrintf("Selected %d %s.", index, clusterName.c_str());

    std::string nodeNames;
    if (!CliReadInputStr(argc, argv, 2, "Node(s) name to add to this cluster: ", &nodeNames)) {
        CliPrint("Node name is required");
        return CLI_INVALID_ARGS;
    }

    std::string roleOpts;
    if (!CliReadInputStr(argc, argv, 3, "Specify roles for these nodes (--all, --etcd, --controlplane, --worker): ", &roleOpts)) {
        CliPrint("Role is required");
        return CLI_INVALID_ARGS;
    }

    //CliPrintf("/usr/local/bin/cubectl config rancher add-node %s %s %s", clusterName.c_str(), nodeNames.c_str(), roleOpts.c_str());
    if (HexSystemF(0, CUBECTL_BIN " config rancher add-node %s %s %s", clusterName.c_str(), nodeNames.c_str(), roleOpts.c_str()) != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
NodeCleanMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="node_clean", [1]=<node name> */)
        return CLI_INVALID_ARGS;

    std::string nodeNames;
    if (!CliReadInputStr(argc, argv, 1, "Node(s) name to clean: ", &nodeNames)) {
        CliPrint("Node name is required");
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, CUBECTL_BIN " config rancher clean-node %s", nodeNames.c_str()) != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
StorageCreateMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="storage_create", [1]=<cluster name> */)
        return CLI_INVALID_ARGS;

    int index;
    std::string clusterName;
    if (CliMatchCmdHelper(argc, argv, 1, "sudo " RANCHER_BIN " context switch <<< 1 >/dev/null 2>&1 && sudo " RANCHER_BIN " cluster ls --format {{.Cluster.Name}} 2>/dev/null", &index, &clusterName) != CLI_SUCCESS) {
        CliPrintf("No kubernetes cluster");
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, CUBECTL_BIN " config rancher create-ceph-storageclass %s", clusterName.c_str()) != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "kubernetes",
    "Work with cube Kubernetes.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

// CLI_MODE("kubernetes", "img",
//     "Work with Kubernetes images.",
//     !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("kubernetes", "image_import", ImgImportMain, NULL,
    "Import container images from usb, or upload images to " CEPHFS_K8S_DIR " for local import.",
    "image_import <usb|local> <file_name>");

CLI_MODE_COMMAND("kubernetes", "image_check", ImgCheckMain, NULL,
    "Check if container images are imported.",
    "image_check");

// CLI_MODE("kubernetes", "node",
//     "Work with Kubernetes images.",
//     !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("kubernetes", "node_add", NodeAddMain, NULL,
    "Add compute nodes to a cluster.",
    "node_add <cluster_name> <node>...");

CLI_MODE_COMMAND("kubernetes", "node_clean", NodeCleanMain, NULL,
    "Clean compute nodes so that it can be re-added to clusters.",
    "node_clean <node>...");

CLI_MODE_COMMAND("kubernetes", "storage_create", StorageCreateMain, NULL,
    "Create a default ceph storage class for a cluster.",
    "storage_create <cluster_name>");
