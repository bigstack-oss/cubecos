// CUBE SDK

#include <hex/log.h>
#include <hex/tuning.h>
#include <hex/config_module.h>
#include <cube/config_file.h>

bool
LoadConfig(const char* filepath, const char* secfmt, const char sep, Configs& config)
{
    bool ret = false;

    FILE *fin = fopen(filepath, "r");
    if (!fin) {
        HexLogWarning("config file %s does not exist", filepath);
        return ret;
    }

    HexTuning_t tun = HexTuningAlloc(fin);
    if (!tun)
        HexLogFatal("malloc failed");

    ret = true;

    int result;
    const char *name, *value;
    char section[HEX_TUNING_NAME_MAXLEN + 1] = GLOBAL_SEC;

    ConfigList settings;
    while ((result = HexTuningParseLineWithD(tun, &name, &value, sep)) != HEX_TUNING_EOF) {
        if (result != HEX_TUNING_SUCCESS) {
            char nextsec[HEX_TUNING_NAME_MAXLEN + 1] = {0};
            if (result == HEX_TUNING_MALFORMED && sscanf(name, secfmt, nextsec) == 1) {
                // Append multiple ']' to the last if it's nested section name
                size_t c = 0;
                while (nextsec[c] == '[')
                    c++;
                if ((strlen(nextsec) + c) < HEX_TUNING_NAME_MAXLEN)
                    memset(&nextsec[strlen(nextsec)], ']', c);

                // assign settings for section
                config[section] = settings;
                // assign new section and clear settings map
                snprintf(section, sizeof(section), "%s", nextsec);
                settings.clear();
                continue;
            }

            // malformed, exceeded buffer, etc.
            HexLogError("Malformed tuning parameter at line %d", HexTuningCurrLine(tun));
            ret = false;
            break;
        }

        settings[name] = value;
    }

    // assign settings for the last section
    config[section] = settings;

    HexTuningRelease(tun);
    fclose(fin);
    return ret;
}

bool
WriteConfig(const char* filepath, const char* secfmt, const char sep, Configs& config)
{
    FILE *fout;
    fout = fopen(filepath, "w+");

    if (!fout) {
        HexLogWarning("config file %s does not exist", filepath);
        return false;
    }

    // global settings should write first
    auto gcfgit = config[GLOBAL_SEC].begin();
    while (gcfgit != config[GLOBAL_SEC].end()) {
        fprintf(fout, "%s %c %s\n", gcfgit->first.c_str(), sep, gcfgit->second.c_str());
        gcfgit++;
    }
    fprintf(fout, "\n");

    auto iter = config.begin();
    while (iter != config.end()) {
        std::string section = iter->first;
        if (section != GLOBAL_SEC) {
            fprintf(fout, secfmt, section.c_str());
            fprintf(fout, "\n");

            ConfigList settings = iter->second;
            auto cfgit = settings.begin();
            while (cfgit != settings.end()) {
                fprintf(fout, "%s %c %s\n", cfgit->first.c_str(), sep, cfgit->second.c_str());
                cfgit++;
            }

            fprintf(fout, "\n");
        }
        iter++;
    }

    fclose(fout);
    return true;
}


bool
DumpConfig(const char* secfmt, const char sep, Configs& config)
{
    return WriteConfig("/dev/stdout", secfmt, sep, config);
}

