// CUBE SDK

#ifndef CLI_EXT_STORAGE_CHANGER_H
#define CLI_EXT_STORAGE_CHANGER_H

#include "include/policy_ext_storage.h"

static const char* LABEL_BACKEND_CONFIG_NAME = "Enter backend name (required): ";
static const char* LABEL_BACKEND_ENDPOINT = "Enter the endpoint of the storage backend: ";
static const char* LABEL_BACKEND_SECRET = "Enter the secret or API token: ";
static const char* LABEL_BACKEND_ACCOUNT = "Enter the user account name: ";
static const char* LABEL_BACKEND_POOL = "Enter storage pool name: ";

class CliExtStorageChanger
{
public:
    bool configure(ExtStoragePolicy *policy, int argc, const char** argv)
    {
        return construct(policy, argc, argv);
    }

private:
    bool checkBackendName(const ExtStorageConfig &cfg, const std::string& name)
    {
        if (!name.length()) {
            CliPrint("backend name is required\n");
            return false;
        }

        for (auto& b : cfg.backends) {
            if (name == b.name) {
                CliPrint("duplicate backend name\n");
                return false;
            }
        }

        return true;
    }

    bool construct(ExtStoragePolicy *policy, int argc, const char** argv)
    {
        CliList actions;
        int actIdx;
        std::string action;

        enum {
            ACTION_ADD = 0,
            ACTION_DELETE,
            ACTION_UPDATE
        };

        actions.push_back("add");
        actions.push_back("delete");
        actions.push_back("update");

        if(CliMatchListHelper(argc, argv, 1, actions, &actIdx, &action) != 0) {
            CliPrint("action type <add|delete|update> is missing or invalid");
            return false;
        }

        ExtStorageConfig cfg;
        policy->getExtStorageConfig(&cfg);
        ExtStorageBackend backend;

        if (actIdx == ACTION_DELETE || actIdx == ACTION_UPDATE) {
            CliList backendList;
            int backendIdx;
            for (auto& b : cfg.backends)
                backendList.push_back(b.name);

            if(CliMatchListHelper(argc, argv, 2, backendList, &backendIdx, &backend.name) != 0) {
                CliPrint("backend name is missing or not found");
                return false;
            }
        }
        else if (actIdx == ACTION_ADD) {
            if (!CliReadInputStr(argc, argv, 2, LABEL_BACKEND_CONFIG_NAME, &backend.name) ||
                !checkBackendName(cfg, backend.name)) {
                return false;
            }
        }

        switch (actIdx) {
            case ACTION_DELETE:
                if (!policy->delBackend(backend.name)) {
                    CliPrintf("failed to delete storage backend: %s", backend.name.c_str());
                    return false;
                }
                break;
            case ACTION_ADD:
            case ACTION_UPDATE: {
                CliList drivers;
                int drvIdx;

                drivers.push_back("cube");
                drivers.push_back("purestorage");

                if(CliMatchListHelper(argc, argv, 3, drivers, &drvIdx, &backend.driver) != 0) {
                    CliPrint("invalid driver");
                    return false;
                }

                if (!CliReadInputStr(argc, argv, 4, LABEL_BACKEND_ENDPOINT, &backend.endpoint) ||
                    backend.endpoint.length() == 0) {
                    CliPrint("endpoint is missing");
                    return false;
                }

                if (!CliReadInputStr(argc, argv, 5, LABEL_BACKEND_ACCOUNT, &backend.account)) {
                    CliPrint("account is invalid");
                    return false;
                }

                if (!CliReadInputStr(argc, argv, 6, LABEL_BACKEND_SECRET, &backend.secret)) {
                    CliPrint("secret is invalid");
                    return false;
                }

                if (backend.driver == "cube") {
                    CliList pools;
                    int pIdx;

                    pools.push_back("cinder-volumes");
                    pools.push_back("volume-backups");
                    CliPrint(LABEL_BACKEND_POOL);
                    if(CliMatchListHelper(argc, argv, 7, pools, &pIdx, &backend.pool) != 0) {
                        CliPrint("invalid pool");
                        return false;
                    }
                }
                else {
                    if (!CliReadInputStr(argc, argv, 7, LABEL_BACKEND_POOL, &backend.pool)) {
                        CliPrint("pool is invalid");
                        return false;
                    }
                }

                CliPrintf("\n%s storage backend: %s", actIdx == ACTION_ADD ? "Adding" : "Updating", backend.name.c_str());
                CliPrintf("driver: %s", backend.driver.c_str());
                CliPrintf("endpoint: %s", backend.endpoint.c_str());
                CliPrintf("account: %s", backend.account.c_str());
                CliPrintf("secret: %s", backend.secret.c_str());
                CliPrintf("pool: %s", backend.pool.c_str());

                if (CliReadConfirmation())
                    policy->setBackend(backend);
                else
                    return false;
                break;
            }
        }

        return true;
    }
};

#endif /* endif CLI_EXT_STORAGE_CHANGER_H */

