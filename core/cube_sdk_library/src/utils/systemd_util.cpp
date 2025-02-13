// CUBE SDK

#include <hex/log.h>
#include <hex/process_util.h>

#include <cube/systemd_util.h>

#define LIMIT 3

bool
SystemdCommitService(const bool enabled, const char* name, const bool retry)
{
    HexUtilSystemF(FWD, 0, "systemctl stop %s", name);

    if (enabled) {
        HexLogDebug("starting %s service", name);
        int cnt = 0;

        do {
            if (HexUtilSystemF(0, 0, "systemctl %s %s", cnt ? "restart" : "start", name) != 0) {
                HexLogError("failed to start %s service", name);
                if (!retry || ++cnt > LIMIT)
                    return false;
            }
            else
                break;
        } while (retry == true);

        HexLogInfo("%s is running", name);
    }
    else {
        HexLogInfo("%s has been stopped", name);
    }

    return true;
}

