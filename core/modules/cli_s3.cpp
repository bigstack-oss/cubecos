// CUBE SDK

#include <sys/stat.h>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

#define STORE_DIR "/store"

static const char* MSG_SEL_USER = "Select a user: ";
static const char* MSG_SEL_KEY = "Select a access key: ";
static const char* MSG_SEL_MEDIA = "Select a media: ";
static const char* MSG_INPUT_FILE = "Input file path: ";
static const char* MSG_BKT_PATH = "Input bucket path: ";
static const char* MSG_OBJ_PATH = "Input object path: ";
static const char* MSG_BKT_MAXSIZE = "Input bucket max-size (-1 for unlimited): ";
static const char* MSG_BKT_MAXOBJS = "Input bucket max-objects (-1 for unlimited): ";
static const char* MSG_BKT_EFFECT = "Input bucket effect (Allow/Deny): ";
static const char* MSG_BKT_IP = "Input bucket IP (ip/netmask): ";

static bool
SelectUser(int argc, const char** argv, std::string *user)
{
    int index;
    std::string cmd;

    cmd = std::string(HEX_SDK) + " os_user_list";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, user, MSG_SEL_USER) != CLI_SUCCESS) {
        CliPrintf("Invalid user");
        return false;
    }

    return true;
}

static int
SelectMedia(int argc, const char** argv, std::string *media, std::string *path, bool isput)
{
    int index;
    std::string dir, file, name;

    if (CliMatchCmdHelper(argc, argv, 2, "echo 'usb\nlocal'", &index, media, MSG_SEL_MEDIA) != CLI_SUCCESS) {
        CliPrintf("Unknown media");
        return false;
    }

    if (index == 0 /* usb */) {
        dir = USB_MNT_DIR;
        CliPrintf("Insert a USB drive into the USB port on the appliance.");
        if (!CliReadConfirmation())
            return true;

        AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
        if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_usb", NULL) != 0) {
            CliPrintf("Could not write to the USB drive. Please check the USB drive and retry the command.\n");
            return true;
        }
    }
    else if (index == 1 /* local */) {
        dir = STORE_DIR;
    }

    if (isput) {
        // list files not dir
        std::string cmd = "ls -p " + dir + " | grep -v /";
        if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &file) != CLI_SUCCESS) {
            CliPrintf("no such file");
            return false;
        }
    }
    else {
        if (!CliReadInputStr(argc, argv, 3, MSG_INPUT_FILE, &file) ||
            file.length() <= 0) {
            CliPrint("file name is required");
            return false;
        }
    }

    *path = dir + "/" + file;

    return true;
}

static int
CreateEc2KeyMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="ec2_key_create" [1]="user" */)
        return CLI_INVALID_ARGS;

    std::string user;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "os_ec2_credentials_create", user.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
DeleteEc2KeyMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="ec2_key_delete" [1]="user" [2]="access_key" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string cmd;
    std::string user;
    std::string key;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    cmd = std::string(HEX_SDK) + " os_access_key_list " + user;
    if(CliMatchCmdHelper(argc, argv, 2, cmd, &index, &key, MSG_SEL_KEY) != CLI_SUCCESS) {
        CliPrintf("Invalid access key");
        return CLI_INVALID_ARGS;
    }

    if (HexSpawn(0, HEX_SDK, "os_ec2_credentials_delete", user.c_str(), key.c_str(), NULL) == 0) {
        CliPrintf("Successfully delete access key %s for user %s", key.c_str(), user.c_str());
    }
    else {
        CliPrintf("Failed to delete access key %s for user %s", key.c_str(), user.c_str());
    }

    return CLI_SUCCESS;
}

static int
ListEc2KeyMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="ec2_key_list" [1]="user" */)
        return CLI_INVALID_ARGS;

    std::string user;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "os_ec2_credentials_list", user.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
S3ListMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="list" [1]="user" [2]="bucket_path" */)
        return CLI_INVALID_ARGS;

    std::string user;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (argc == 3)
        HexSpawn(0, HEX_SDK, "os_s3_list", user.c_str(), argv[2], NULL);
    else
        HexSpawn(0, HEX_SDK, "os_s3_list_all", user.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
BucketCreateMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="create" [1]="user" [2]="bucket_path" */)
        return CLI_INVALID_ARGS;

    std::string user, bktpath;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 2, MSG_BKT_PATH, &bktpath) ||
        bktpath.length() <= 0) {
        CliPrint("bucket path is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_bucket_create", user.c_str(), bktpath.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
BucketRemoveMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="remove" [1]="user" [2]="bucket_path" */)
        return CLI_INVALID_ARGS;

    std::string user, bktpath;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 2, MSG_BKT_PATH, &bktpath) ||
        bktpath.length() <= 0) {
        CliPrint("bucket path is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_bucket_remove", user.c_str(), bktpath.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
BucketQuotaMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="remove" [1]="user" [2]="bucket_path" [3]="max_size" [4]="max_objects" */)
        return CLI_INVALID_ARGS;

    std::string user, bktpath, bktmaxsize, bktmaxobjs;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 2, MSG_BKT_PATH, &bktpath) ||
        bktpath.length() <= 0) {
        CliPrint("bucket path is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, MSG_BKT_MAXSIZE, &bktmaxsize) ||
        bktmaxsize.length() <= 0) {
        bktmaxsize="-1";
        CliPrint("use default bucket max size: unlimited");
    }

    if (!CliReadInputStr(argc, argv, 4, MSG_BKT_MAXOBJS, &bktmaxobjs) ||
        bktmaxobjs.length() <= 0) {
        bktmaxobjs="-1";
        CliPrint("use default bucket max objects: unlimited");
    }

    HexSpawn(0, HEX_SDK, "os_s3_bucket_quota", user.c_str(), bktpath.c_str(), bktmaxsize.c_str(), bktmaxobjs.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
BucketStatsMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="list" [1]="user" [2]="bucket_path" */)
        return CLI_INVALID_ARGS;

    std::string user;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (argc == 3)
        HexSpawn(0, HEX_SDK, "os_s3_bucket_stats", user.c_str(), argv[2], NULL);
    else
        HexSpawn(0, HEX_SDK, "os_s3_bucket_stats", user.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
BucketSetpolicyMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="remove" [1]="user" [2]="bucket_path" [3]="effect" [4]="ip" */)
        return CLI_INVALID_ARGS;

    std::string user, bktpath, bkteffect, bktip;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 2, MSG_BKT_PATH, &bktpath) ||
        bktpath.length() <= 0) {
        CliPrint("bucket path is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, MSG_BKT_EFFECT, &bkteffect) ||
        bkteffect.length() <= 0) {
        CliPrint("bucket policy effect (Allow/Deny) is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, MSG_BKT_IP, &bktip) ||
        bktip.length() <= 0) {
        CliPrint("bucket policy ip (ip/netmask) is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_bucket_setpolicy", user.c_str(), bktpath.c_str(), bkteffect.c_str(), bktip.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
BucketInfoMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="list" [1]="user" [2]="bucket_path" */)
        return CLI_INVALID_ARGS;

    std::string user, bktpath;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 2, MSG_BKT_PATH, &bktpath) ||
        bktpath.length() <= 0) {
        CliPrint("bucket path is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_bucket_info", user.c_str(), bktpath.c_str(), NULL);

    return CLI_SUCCESS;
}


static int
ObjectPutMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="put" [1]="user" [2]="<usb|local>" [3]="<fname>" [4]="<objec_path>" */)
        return CLI_INVALID_ARGS;

    std::string user, media, fullpath, objpath;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!SelectMedia(argc, argv, &media, &fullpath, true))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 4, MSG_OBJ_PATH, &objpath) ||
        objpath.length() <= 0) {
        CliPrint("object path is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_object_put", user.c_str(), fullpath.c_str(), objpath.c_str(), NULL);

    if (media == "usb") {
        CliPrintf("Uploading object to %s3 complete. It is safe to remove the USB drive.", objpath.c_str());
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    }

    return CLI_SUCCESS;
}

static int
ObjectGetMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="get" [1]="user" [2]="<usb|local>" [3]="<fname>" [4]="<objec_path>" */)
        return CLI_INVALID_ARGS;

    std::string user, media, fullpath, objpath;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!SelectMedia(argc, argv, &media, &fullpath, false))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 4, MSG_OBJ_PATH, &objpath) ||
        objpath.length() <= 0) {
        CliPrint("object path is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_object_get", user.c_str(), objpath.c_str(), fullpath.c_str(), NULL);

    if (media == "usb") {
        CliPrintf("Download object %s3 complete. It is safe to remove the USB drive.", objpath.c_str());
        HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
    }

    return CLI_SUCCESS;
}

static int
ObjectDelMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="delete" [1]="user" [2]="<objec_path>" */)
        return CLI_INVALID_ARGS;

    std::string user, media, fullpath, objpath;

    if (!SelectUser(argc, argv, &user))
        return CLI_INVALID_ARGS;

    if (!CliReadInputStr(argc, argv, 2, MSG_OBJ_PATH, &objpath) ||
        objpath.length() <= 0) {
        CliPrint("object path is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_s3_object_delete", user.c_str(), objpath.c_str(), NULL);

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "s3",
    "Work with S3 objects and settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("s3", "ec2_key_create", CreateEc2KeyMain, NULL,
    "create ec2 credentials for a keystone user.",
    "ec2_key_create [<user>]");

CLI_MODE_COMMAND("s3", "ec2_key_delete", DeleteEc2KeyMain, NULL,
    "delete ec2 credentials for a keystone user.",
    "ec2_key_delete [<user>] [<access_key>]");

CLI_MODE_COMMAND("s3", "ec2_key_list", ListEc2KeyMain, NULL,
    "list ec2 credentials for a keystone user.",
    "ec2_key_list [<user>]");

CLI_MODE_COMMAND("s3", "list", S3ListMain, NULL,
    "list objects/buckets under a given path.",
    "list [<user>] [bucket_path]");

CLI_MODE("s3", "bucket",
    "Work with s3 bucket.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("bucket", "create", BucketCreateMain, NULL,
    "create a bucket for a user.",
    "create [<user>] [<bucket_path>]");

CLI_MODE_COMMAND("bucket", "remove", BucketRemoveMain, NULL,
    "remove a bucket for a user.",
    "remove [<user>] [<bucket_path>]");

CLI_MODE_COMMAND("bucket", "quota", BucketQuotaMain, NULL,
    "quota setting of specified bucket for a user.",
    "quota [<user>] [<bucket_path>] [<max_size>] [<max_objects>]");

CLI_MODE_COMMAND("bucket", "stats", BucketStatsMain, NULL,
    "stats of specified bucket path.",
    "stats [<user>] [bucket_path]");

CLI_MODE_COMMAND("bucket", "setpolicy", BucketSetpolicyMain, NULL,
    "setpolicy for specified bucket for a user.",
    "setpolicy [<user>] [<bucket_path>] [<Allow|Deny>] [<ip/netmask>]");

CLI_MODE_COMMAND("bucket", "info", BucketInfoMain, NULL,
    "info of specified bucket path.",
    "info [<user>] [bucket_path]");

CLI_MODE("s3", "object",
    "Work with s3 object. it's working under " STORE_DIR " directory for the local option.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("object", "put", ObjectPutMain, NULL,
    "Upload a object from a media path to a bucket for a user.",
    "put [<user>] [<usb|local>] [<filename>] [<object_path>]");

CLI_MODE_COMMAND("object", "get", ObjectGetMain, NULL,
    "Download a object of a user into a media.",
    "get [<user>] [<usb|local>] [<filename>] [<object_path>]");

CLI_MODE_COMMAND("object", "delete", ObjectDelMain, NULL,
    "delete a object for a user.",
    "delete [<user>] [<object_path>]");

