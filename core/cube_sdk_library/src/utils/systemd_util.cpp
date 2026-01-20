// CUBE SDK

#include <cube/systemd_util.h>

static const int LIMIT = 3;

bool SystemdCommitService(const bool enabled, const char* name, const bool retry, const bool quiet)
{
    HexUtilSystemF(FWD, 0, "systemctl stop %s", name);

    if (enabled) {
        HexLogDebug("starting %s service", name);
        int cnt = 0;

        do {
            int ret = 0;
            const std::string command = std::string("systemctl ")
                + (cnt ? "restart" : "start") + " " + name;

            if (quiet) {
                HexLogInfo("Executing: %s", command.c_str());
                const ExecSyncResult r = ExecBashSync(
                    0,
                    false,
                    false,
                    {},
                    command);
                ret = r.exitCode;
            } else {
                ret = HexUtilSystemF(AWY, 0, "%s", command.c_str());
            }

            if (ret != 0) {
                HexLogError("failed to start %s service", name);
                if (!retry || ++cnt > LIMIT)
                    return false;
            } else {
                break;
            }
        } while (retry == true);

        HexLogInfo("%s is running", name);
    } else {
        HexLogInfo("%s has been stopped", name);
    }

    return true;
}

bool SystemdCommitService(const bool enabled, const char* name, const bool retry)
{
    return SystemdCommitService(enabled, name, retry, false);
}
