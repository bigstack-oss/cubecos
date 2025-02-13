// HEX SDK

#include <unistd.h>
#include <limits.h>
#include <sys/time.h>
#include <dirent.h>

#include <hex/process.h>
#include <hex/log.h>
#include <hex/string_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>

static const char SUPPORT_DIR[] = "/var/support";
static const char VOL_META_EXT[] = ".volume-meta";
static const size_t VOL_META_EXT_LEN = sizeof(VOL_META_EXT) - 1;

// using external tunings
CONFIG_TUNING_SPEC_STR(SYS_VENDOR_NAME);
CONFIG_TUNING_SPEC_STR(SYS_VENDOR_VERSION);

// parse tunings
PARSE_TUNING_STR(s_vendorName, SYS_VENDOR_NAME);
PARSE_TUNING_STR(s_vendorVersion, SYS_VENDOR_VERSION);

static bool
ResolvePath(const char *arg, const char *dir, std::string& path)
{
    // Always search for file in support directory
    // even if user supplied an absolute path
    std::string tmp = dir;
    tmp += '/';
    tmp += basename(arg);
    if (access(tmp.c_str(), F_OK) == 0) {
        path = tmp;
        return true;
    }

    return false;
}

static bool
GetVolumeMetaName(const char* hostname, std::string *name)
{
    // [VENDOR_NAME]_[VENDOR_VERSION]_[%Y%m%d-%H%M%S.%US]_[HOSTNAME].volume-meta

    *name = s_vendorName;
    *name += '_';
    *name += s_vendorVersion;
    *name += '_';

    struct timeval now;
    if (gettimeofday(&now, NULL) != 0) {
        HexLogError("Could not get current time.");
        return false;
    }

    struct tm *tm = localtime(&now.tv_sec);
    char buffer[32];
    strftime(buffer, 32, "%Y%m%d-%H%M%S", tm);

    *name += buffer;
    *name += '.';
    snprintf(buffer, sizeof(buffer), "%ld", now.tv_usec);
    *name += buffer;

    *name += '_';

    if (hostname != NULL) {
        *name += hostname;
    }
    else {
        char buf[HOST_NAME_MAX + 1];
        if (gethostname(buf, HOST_NAME_MAX + 1) == 0 && strncmp(buf, "(none)", 6) != 0) {
            *name += buf;
        }
        else {
            *name += "unconfigured";
        }
    }

    *name += VOL_META_EXT;

    return true;
}

static bool
CreateVolumeMeta(const std::string &name, const std::string &volumes)
{
    std::string path = SUPPORT_DIR;
    path += "/";
    path += name;

    std::vector<std::string> vols = hex_string_util::split(volumes, ',');
    std::vector<const char*> command;
    command.push_back(HEX_SDK);
    command.push_back("os_export_volume");
    command.push_back(path.c_str());
    for (auto& v : vols)
        command.push_back(v.c_str());
    command.push_back(0);

    if (HexSpawnV(0, (char* const*)&command[0]) != 0) {
        HexLogError("Could not create volume meta file.");
        return false;
    }

    return true;

}

static bool
ParseSys(const char *name, const char *value, bool isNew)
{
    bool r = true;

    TuneStatus s = ParseTune(name, value, isNew);
    if (s == TUNE_INVALID_VALUE) {
        HexLogError("Invalid settings value \"%s\" = \"%s\"", name, value);
        r = false;
    }

    return r;
}

static void
CreateUsage(void)
{
    fprintf(stderr, "Usage: %s volume_meta_create [ -h <hostname> ] <comma-separated volume list>\n", HexLogProgramName());
}

static int
CreateMain(int argc, char **argv)
{
    const char *hostname = NULL;

    optind = 0;
    int opt;
    while ((opt = getopt(argc, (char *const *)argv, "h:")) != -1) {
        switch (opt) {
        case 'h':
            hostname = optarg;
            break;
        default:
            CreateUsage();
            return EXIT_FAILURE;
        }
    }

    const char *volist = NULL;
    if (optind == argc - 1) {
        volist = argv[optind];
    }
    else if (optind != argc) {
        CreateUsage();
        return EXIT_FAILURE;
    }

    std::string name;
    if (!GetVolumeMetaName(hostname, &name)) {
        return EXIT_FAILURE;
    }

    HexLogDebugN(FWD, "Creating volume meta file");

    if (!CreateVolumeMeta(name, volist)) {
        return EXIT_FAILURE;
    }

    // Echo new volume meta filename to stdout
    HexLogDebugN(FWD, "volume meta file: %s", name.c_str());
    printf("%s\n", name.c_str());
    return EXIT_SUCCESS;
}

static void
ListUsage(void)
{
    fprintf(stderr, "Usage: %s volume_meta_list\n", HexLogProgramName());
}

static int
ListMain(int argc, char **argv)
{
    if (argc != 1) {
        ListUsage();
        return 1;
    }

    HexLogDebugN(FWD, "Listing volume meta files");

    DIR *dir = opendir(SUPPORT_DIR);
    if (dir == NULL)
        HexLogFatal("Support directory not found: %s", SUPPORT_DIR);

    while (1) {
        struct dirent *p = readdir(dir);
        if (p == NULL)
            break;

        // Echo all volume meta names to stdout
        size_t len = strlen(p->d_name);
        if (len > VOL_META_EXT_LEN && strcmp(p->d_name + len - VOL_META_EXT_LEN, VOL_META_EXT) == 0) {
            HexLogDebugN(FWD, "volume meta file: %s", p->d_name);
            printf("%s\n", p->d_name);
        }
    }

    closedir(dir);

    return 0;
}

static void
ApplyUsage(void)
{
    fprintf(stderr, "Usage: %s volume_meta_apply <user name> <project name> <hostname> <volume meta file>\n", HexLogProgramName());
}

static int
ApplyMain(int argc, char **argv)
{
    if (argc != 5) {
        ApplyUsage();
        return 1;
    }

    HexLogDebugN(FWD, "Applying volume meta file");

    const char *user = argv[1];
    const char *project = argv[2];
    const char *host = argv[3];

    std::string path;
    if (!ResolvePath(argv[4], SUPPORT_DIR, path)) {
        HexLogError("Volume meta file not found: %s", argv[1]);
        return EXIT_FAILURE;
    }

    HexLogDebugN(FWD, "Volume meta file: %s", path.c_str());

    std::vector<const char*> command;
    command.push_back(HEX_SDK);
    command.push_back("os_import_volume");
    command.push_back(user);
    command.push_back(project);
    command.push_back(host);
    command.push_back(path.c_str());
    command.push_back(0);

    return HexExitStatus(HexSpawnV(0, (char* const*)&command[0]));
}

static void
DeleteUsage(void)
{
    fprintf(stderr, "Usage: %s volume_meta_delete <volume meta file>\n", HexLogProgramName());
}

static int
DeleteMain(int argc, char* argv[])
{
    if (argc != 2) {
        DeleteUsage();
        return 1;
    }

    HexLogDebugN(FWD, "Deleting volume meta file");

    std::string path;
    if (!ResolvePath(argv[1], SUPPORT_DIR, path))
        HexLogFatal("Volume meta file not found: %s", argv[1]);

    HexLogDebugN(FWD, "Volume meta file: %s", path.c_str());

    unlink(path.c_str());
    return 0;
}

CONFIG_MODULE(volume-meta, 0, 0, 0, 0, 0);
CONFIG_OBSERVES(volume-meta, sys, ParseSys, 0);

CONFIG_COMMAND_WITH_SETTINGS(volume_meta_create, CreateMain, CreateUsage);
CONFIG_COMMAND(volume_meta_list, ListMain, ListUsage);
CONFIG_COMMAND(volume_meta_apply, ApplyMain, ApplyUsage);
CONFIG_COMMAND(volume_meta_delete, DeleteMain, DeleteUsage);

